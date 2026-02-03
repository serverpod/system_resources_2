import 'dart:io';

import 'cgroup_detector.dart';

/// CPU monitoring using cgroup metrics and /proc/loadavg fallback.
///
/// This approach reads actual CPU time consumed from cgroup accounting,
/// which works in containerized environments including gVisor.
///
/// For Linux hosts without cgroups, falls back to `/proc/loadavg`.
class CgroupCpu {
  /// Path to /proc/loadavg for host fallback
  static const procLoadAvg = '/proc/loadavg';

  /// Previous CPU usage reading for delta calculation
  static int? _previousMicros;
  static DateTime? _previousTime;

  /// Reads the total CPU time consumed in microseconds.
  ///
  /// For cgroup v2: reads `usage_usec` from `/sys/fs/cgroup/cpu.stat`
  /// For cgroup v1: reads nanoseconds from `/sys/fs/cgroup/cpuacct/cpuacct.usage`
  ///                and converts to microseconds
  ///
  /// Returns 0 if unable to read CPU stats.
  static int getUsageMicros() {
    final version = CgroupDetector.detectVersion();

    if (version == CgroupVersion.v2) {
      return _readCgroupV2Usage();
    } else if (version == CgroupVersion.v1) {
      return _readCgroupV1Usage();
    }

    return 0;
  }

  /// Reads CPU usage from cgroup v2.
  static int _readCgroupV2Usage() {
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
  static int _readCgroupV1Usage() {
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

  /// Gets the CPU limit in millicores (1000 = 1 full CPU core).
  ///
  /// For cgroup v2: reads `/sys/fs/cgroup/cpu.max` (format: "quota period")
  /// For cgroup v1: reads `cpu.cfs_quota_us` and `cpu.cfs_period_us`
  ///
  /// Returns -1 if unlimited or unable to determine.
  static int getLimitMillicores() {
    final version = CgroupDetector.detectVersion();

    if (version == CgroupVersion.v2) {
      return _readCgroupV2Limit();
    } else if (version == CgroupVersion.v1) {
      return _readCgroupV1Limit();
    }

    return -1;
  }

  /// Reads CPU limit from cgroup v2.
  static int _readCgroupV2Limit() {
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
  static int _readCgroupV1Limit() {
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

  /// Gets the CPU limit in cores (fractional).
  ///
  /// Returns the container's CPU limit, or the host CPU count if unlimited
  /// or not in a container.
  static double getLimitCores() {
    final millicores = getLimitMillicores();
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

  /// Calculates CPU usage in millicores based on delta since last call.
  ///
  /// This method maintains state between calls to calculate the rate of
  /// CPU consumption. First call returns 0 as there's no previous reading.
  ///
  /// Formula: millicores = (delta_cpu_micros / interval_micros) * 1000
  ///
  /// Returns 0 on first call or if unable to calculate.
  static int getUsageMillicores() {
    final now = DateTime.now();
    final currentMicros = getUsageMicros();

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
  /// Returns a value where 1.0 means 100% of CPU limit is being used.
  /// Values can exceed 1.0 if usage exceeds limit (CPU throttling may occur).
  ///
  /// Returns 0.0 on first call (no delta available yet).
  static double getLoad() {
    final millicores = getUsageMillicores();
    final limitMillicores = getLimitMillicores();

    if (millicores <= 0) return 0.0;

    if (limitMillicores > 0) {
      return millicores / limitMillicores;
    }

    // If unlimited, calculate against host CPU count
    final hostCores = Platform.numberOfProcessors;
    return millicores / (hostCores * 1000);
  }

  /// Clears the cached previous reading. Useful for testing.
  static void clearState() {
    _previousMicros = null;
    _previousTime = null;
  }

  /// Gets the CPU load average normalized by CPU limit/count.
  ///
  /// This provides Serverpod API compatibility. The behavior depends on
  /// the environment:
  ///
  /// - **Container (cgroups)**: Uses cgroup CPU accounting (delta-based).
  ///   First call returns 0.0, subsequent calls return actual load.
  /// - **Linux host**: Reads `/proc/loadavg` (1-minute average) and
  ///   normalizes by CPU count.
  ///
  /// Returns a value where 1.0 means 100% CPU utilization.
  static double getLoadAvg() {
    final version = CgroupDetector.detectVersion();

    // In container: use cgroup-based calculation
    if (version != CgroupVersion.none) {
      return getLoad();
    }

    // On host: read /proc/loadavg
    return _readProcLoadAvg();
  }

  /// Reads 1-minute load average from /proc/loadavg and normalizes by CPU count.
  ///
  /// /proc/loadavg format: "0.00 0.01 0.05 1/234 12345"
  /// First value is 1-minute load average.
  static double _readProcLoadAvg() {
    try {
      final content = File(procLoadAvg).readAsStringSync();
      final parts = content.split(' ');
      if (parts.isNotEmpty) {
        final loadAvg = double.tryParse(parts[0]);
        if (loadAvg != null) {
          // Normalize by CPU count
          final cpuCount = Platform.numberOfProcessors;
          return loadAvg / cpuCount;
        }
      }
    } catch (_) {}
    return 0.0;
  }
}
