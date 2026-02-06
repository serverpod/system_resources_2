import 'dart:io';

import 'cgroup_detector.dart';

/// CPU monitoring using cgroup metrics and /proc/loadavg fallback.
///
/// Provides per-cgroup-version reader methods that are called directly
/// from `SystemResources` via a flat switch on [DetectedPlatform].
///
/// For Linux hosts without cgroups, falls back to `/proc/loadavg`.
class CgroupCpu {
  /// Previous CPU usage reading for delta calculation
  static int? _previousMicros;
  static DateTime? _previousTime;

  // ---------------------------------------------------------------------------
  // CPU usage readers (microseconds)
  // ---------------------------------------------------------------------------

  /// Reads CPU usage from cgroup v2.
  ///
  /// Parses `usage_usec` from `/sys/fs/cgroup/cpu.stat`.
  /// Returns 0 if unable to read.
  static int readV2UsageMicros() {
    try {
      final content = File(CgroupDetector.cgroupV2CpuStat).readAsStringSync();
      for (final line in content.split('\n')) {
        if (line.startsWith('usage_usec')) {
          final parts = line.split(' ');
          if (parts.length >= 2) {
            return int.tryParse(parts[1]) ?? 0;
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Reads CPU usage from cgroup v1 (converts nanoseconds to microseconds).
  ///
  /// Tries both `/sys/fs/cgroup/cpuacct/cpuacct.usage` and the
  /// `cpu,cpuacct` alternative mount.
  /// Returns 0 if unable to read.
  static int readV1UsageMicros() {
    for (final path in [
      CgroupDetector.cgroupV1CpuAcctUsage,
      CgroupDetector.cgroupV1CpuAcctUsageAlt,
    ]) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          final nanos = int.tryParse(file.readAsStringSync().trim());
          if (nanos != null) {
            return nanos ~/ 1000; // Convert to microseconds
          }
        }
      } catch (_) {}
    }
    return 0;
  }

  // ---------------------------------------------------------------------------
  // CPU limit readers (millicores)
  // ---------------------------------------------------------------------------

  /// Reads CPU limit from cgroup v2.
  ///
  /// Parses `/sys/fs/cgroup/cpu.max` (format: `"quota period"`).
  /// Returns -1 if unlimited or unable to determine.
  static int readV2LimitMillicores() {
    try {
      final content =
          File(CgroupDetector.cgroupV2CpuMax).readAsStringSync().trim();
      final parts = content.split(' ');
      if (parts.length >= 2) {
        if (parts[0] == 'max') return -1; // Unlimited

        final quota = int.tryParse(parts[0]);
        final period = int.tryParse(parts[1]);
        if (quota != null && period != null && period > 0) {
          return (quota * 1000) ~/ period;
        }
      }
    } catch (_) {}
    return -1;
  }

  /// Reads CPU limit from cgroup v1.
  ///
  /// Reads `cpu.cfs_quota_us` and `cpu.cfs_period_us` from both the
  /// primary and alternative mount paths.
  /// Returns -1 if unlimited or unable to determine.
  static int readV1LimitMillicores() {
    final quotaPaths = [
      CgroupDetector.cgroupV1CpuQuota,
      CgroupDetector.cgroupV1CpuQuotaAlt,
    ];
    final periodPaths = [
      CgroupDetector.cgroupV1CpuPeriod,
      CgroupDetector.cgroupV1CpuPeriodAlt,
    ];

    for (var i = 0; i < quotaPaths.length; i++) {
      try {
        final quotaFile = File(quotaPaths[i]);
        final periodFile = File(periodPaths[i]);

        if (quotaFile.existsSync() && periodFile.existsSync()) {
          final quota = int.tryParse(quotaFile.readAsStringSync().trim());
          final period = int.tryParse(periodFile.readAsStringSync().trim());

          if (quota != null && period != null) {
            if (quota == -1) return -1; // Unlimited
            if (period > 0) {
              return (quota * 1000) ~/ period;
            }
          }
        }
      } catch (_) {}
    }
    return -1;
  }

  // ---------------------------------------------------------------------------
  // /proc fallback
  // ---------------------------------------------------------------------------

  /// Reads 1-minute load average from /proc/loadavg and normalizes by CPU count.
  ///
  /// `/proc/loadavg` format: `"0.00 0.01 0.05 1/234 12345"`
  /// First value is 1-minute load average.
  static double readProcLoadAvg() {
    try {
      final content = File(CgroupDetector.procLoadAvg).readAsStringSync();
      final parts = content.split(' ');
      if (parts.isNotEmpty) {
        final loadAvg = double.tryParse(parts[0]);
        if (loadAvg != null) {
          final cpuCount = Platform.numberOfProcessors;
          return loadAvg / cpuCount;
        }
      }
    } catch (_) {}
    return 0.0;
  }

  // ---------------------------------------------------------------------------
  // Delta-based calculations (stateful)
  // ---------------------------------------------------------------------------

  /// Calculates CPU usage in millicores based on delta since last call.
  ///
  /// Requires [usageMicrosReader] — a callback that reads the current
  /// cumulative CPU usage in microseconds for the detected cgroup version.
  ///
  /// First call returns 0 as there's no previous reading.
  ///
  /// Formula: `millicores = (delta_cpu_micros / interval_micros) * 1000`
  static int getUsageMillicores(int Function() usageMicrosReader) {
    final now = DateTime.now();
    final currentMicros = usageMicrosReader();

    if (_previousMicros == null || _previousTime == null) {
      _previousMicros = currentMicros;
      _previousTime = now;
      return 0;
    }

    final microsDelta = currentMicros - _previousMicros!;
    final intervalMicros = now.difference(_previousTime!).inMicroseconds;

    _previousMicros = currentMicros;
    _previousTime = now;

    if (intervalMicros <= 0) return 0;

    return ((microsDelta / intervalMicros) * 1000).round();
  }

  /// Gets CPU load as a fraction of the limit.
  ///
  /// [usageMicrosReader] and [limitMillicoresReader] are callbacks for
  /// the detected cgroup version.
  ///
  /// Returns a value where 1.0 means 100% of CPU limit is being used.
  /// Values can exceed 1.0 if usage exceeds limit (CPU throttling may occur).
  ///
  /// Returns 0.0 on first call (no delta available yet).
  static double getLoad(
    int Function() usageMicrosReader,
    int Function() limitMillicoresReader,
  ) {
    final millicores = getUsageMillicores(usageMicrosReader);
    if (millicores <= 0) return 0.0;

    final limitCores = getLimitCores(limitMillicoresReader);
    return millicores / (limitCores * 1000);
  }

  /// Gets the CPU limit in cores (fractional).
  ///
  /// [limitMillicoresReader] is a callback for the detected cgroup version.
  ///
  /// Returns the container's CPU limit, or the host CPU count if unlimited.
  static double getLimitCores(int Function() limitMillicoresReader) {
    final millicores = limitMillicoresReader();
    if (millicores > 0) {
      return millicores / 1000.0;
    }

    // Fallback: check environment variable (for gVisor)
    final envLimit = Platform.environment['SYSRES_CPU_CORES'];
    if (envLimit != null) {
      final cores = double.tryParse(envLimit);
      if (cores != null && cores > 0) {
        return cores;
      }
    }

    // Fallback: host CPU count
    return Platform.numberOfProcessors.toDouble();
  }

  /// Clears the cached previous reading. Useful for testing.
  static void clearState() {
    _previousMicros = null;
    _previousTime = null;
  }
}
