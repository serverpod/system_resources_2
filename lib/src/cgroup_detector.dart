import 'dart:io';

/// Cgroup version detected on the system.
enum CgroupVersion {
  /// Cgroup v1 (legacy hierarchy)
  v1,

  /// Cgroup v2 (unified hierarchy)
  v2,

  /// No cgroup detected (not in container or unsupported)
  none,
}

/// The resolved runtime environment, combining OS and cgroup detection
/// into a single flat enum for dispatch.
enum DetectedPlatform {
  /// macOS — uses native FFI for all metrics.
  macOS,

  /// Linux with cgroup v2 (unified hierarchy).
  linuxCgroupV2,

  /// Linux with cgroup v1 (legacy hierarchy).
  linuxCgroupV1,

  /// Linux without cgroups — falls back to /proc.
  linuxHost,

  /// Unsupported OS — all metrics return zero.
  unsupported,
}

/// Detects cgroup version, platform, and container environment.
class CgroupDetector {
  static DetectedPlatform? _cachedPlatform;
  static bool? _cachedIsContainer;

  /// Cgroup v2 paths
  static const cgroupV2CpuStat = '/sys/fs/cgroup/cpu.stat';
  static const cgroupV2CpuMax = '/sys/fs/cgroup/cpu.max';
  static const cgroupV2MemoryCurrent = '/sys/fs/cgroup/memory.current';
  static const cgroupV2MemoryMax = '/sys/fs/cgroup/memory.max';

  /// Cgroup v1 paths
  static const cgroupV1CpuAcctUsage = '/sys/fs/cgroup/cpuacct/cpuacct.usage';
  static const cgroupV1CpuAcctUsageAlt =
      '/sys/fs/cgroup/cpu,cpuacct/cpuacct.usage';
  static const cgroupV1CpuQuota = '/sys/fs/cgroup/cpu/cpu.cfs_quota_us';
  static const cgroupV1CpuQuotaAlt =
      '/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_quota_us';
  static const cgroupV1CpuPeriod = '/sys/fs/cgroup/cpu/cpu.cfs_period_us';
  static const cgroupV1CpuPeriodAlt =
      '/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_period_us';
  static const cgroupV1MemoryUsage =
      '/sys/fs/cgroup/memory/memory.usage_in_bytes';
  static const cgroupV1MemoryLimit =
      '/sys/fs/cgroup/memory/memory.limit_in_bytes';

  /// Host fallback paths
  static const procMeminfo = '/proc/meminfo';
  static const procStat = '/proc/stat';
  static const procLoadAvg = '/proc/loadavg';

  /// Detects the runtime platform and cgroup environment.
  ///
  /// Combines OS detection and cgroup version probing into a single
  /// cached [DetectedPlatform] value used for dispatch.
  static DetectedPlatform detectPlatform() {
    if (_cachedPlatform != null) return _cachedPlatform!;

    if (Platform.isMacOS) {
      _cachedPlatform = DetectedPlatform.macOS;
    } else if (Platform.isLinux) {
      if (File(cgroupV2CpuStat).existsSync()) {
        _cachedPlatform = DetectedPlatform.linuxCgroupV2;
      } else if (File(cgroupV1CpuAcctUsage).existsSync() ||
          File(cgroupV1CpuAcctUsageAlt).existsSync()) {
        _cachedPlatform = DetectedPlatform.linuxCgroupV1;
      } else {
        _cachedPlatform = DetectedPlatform.linuxHost;
      }
    } else {
      _cachedPlatform = DetectedPlatform.unsupported;
    }

    return _cachedPlatform!;
  }

  /// Detects the cgroup version available on this system.
  ///
  /// Derived from [detectPlatform] for backward compatibility.
  ///
  /// Returns [CgroupVersion.v2] if cgroup v2 files are present,
  /// [CgroupVersion.v1] if cgroup v1 files are present,
  /// or [CgroupVersion.none] if no cgroups are detected.
  static CgroupVersion detectVersion() => switch (detectPlatform()) {
        DetectedPlatform.linuxCgroupV2 => CgroupVersion.v2,
        DetectedPlatform.linuxCgroupV1 => CgroupVersion.v1,
        _ => CgroupVersion.none,
      };

  /// Returns true if running in a detected container environment.
  ///
  /// Container detection is based on the presence of cgroup memory limits.
  /// Returns false on non-Linux platforms or when no container limit is set.
  static bool isContainerEnv() {
    if (_cachedIsContainer != null) return _cachedIsContainer!;

    _cachedIsContainer = switch (detectPlatform()) {
      DetectedPlatform.linuxCgroupV2 => _detectContainerV2(),
      DetectedPlatform.linuxCgroupV1 => _detectContainerV1(),
      _ => false,
    };

    return _cachedIsContainer!;
  }

  /// Checks cgroup v2 memory.max for a container limit.
  static bool _detectContainerV2() {
    try {
      final content = File(cgroupV2MemoryMax).readAsStringSync().trim();
      // "max" means unlimited (likely host), a number means container limit
      return content != 'max';
    } catch (_) {
      return false;
    }
  }

  /// Checks cgroup v1 memory.limit_in_bytes for a container limit.
  static bool _detectContainerV1() {
    try {
      final limit =
          int.tryParse(File(cgroupV1MemoryLimit).readAsStringSync().trim());
      // Very large values indicate no limit (host)
      // Typically 9223372036854771712 or similar
      return limit != null && limit < 9000000000000000000;
    } catch (_) {
      return false;
    }
  }

  /// Clears cached detection results. Useful for testing.
  static void clearCache() {
    _cachedPlatform = null;
    _cachedIsContainer = null;
  }
}
