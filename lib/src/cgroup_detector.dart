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

/// Detects cgroup version and container environment.
class CgroupDetector {
  static CgroupVersion? _cachedVersion;
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

  /// Detects the cgroup version available on this system.
  ///
  /// Returns [CgroupVersion.v2] if cgroup v2 files are present,
  /// [CgroupVersion.v1] if cgroup v1 files are present,
  /// or [CgroupVersion.none] if no cgroups are detected.
  static CgroupVersion detectVersion() {
    if (_cachedVersion != null) return _cachedVersion!;

    if (!Platform.isLinux) {
      _cachedVersion = CgroupVersion.none;
      return _cachedVersion!;
    }

    // Check for cgroup v2 first (preferred)
    if (File(cgroupV2CpuStat).existsSync()) {
      _cachedVersion = CgroupVersion.v2;
      return _cachedVersion!;
    }

    // Check for cgroup v1
    if (File(cgroupV1CpuAcctUsage).existsSync() ||
        File(cgroupV1CpuAcctUsageAlt).existsSync()) {
      _cachedVersion = CgroupVersion.v1;
      return _cachedVersion!;
    }

    _cachedVersion = CgroupVersion.none;
    return _cachedVersion!;
  }

  /// Returns true if running in a detected container environment.
  ///
  /// Container detection is based on the presence of cgroup CPU or memory
  /// accounting files. Returns false on non-Linux platforms.
  static bool isContainerEnv() {
    if (_cachedIsContainer != null) return _cachedIsContainer!;

    if (!Platform.isLinux) {
      _cachedIsContainer = false;
      return false;
    }

    final version = detectVersion();
    if (version == CgroupVersion.v2) {
      // Check if we have memory limits set (indicates container)
      final memMax = File(cgroupV2MemoryMax);
      if (memMax.existsSync()) {
        try {
          final content = memMax.readAsStringSync().trim();
          // "max" means unlimited (likely host), a number means container limit
          _cachedIsContainer = content != 'max';
          return _cachedIsContainer!;
        } catch (_) {}
      }
    } else if (version == CgroupVersion.v1) {
      // Check if memory limit is set
      final memLimit = File(cgroupV1MemoryLimit);
      if (memLimit.existsSync()) {
        try {
          final limit = int.tryParse(memLimit.readAsStringSync().trim());
          // Very large values indicate no limit (host)
          // Typically 9223372036854771712 or similar
          _cachedIsContainer = limit != null && limit < 9000000000000000000;
          return _cachedIsContainer!;
        } catch (_) {}
      }
    }

    _cachedIsContainer = false;
    return false;
  }

  /// Clears cached detection results. Useful for testing.
  static void clearCache() {
    _cachedVersion = null;
    _cachedIsContainer = null;
  }
}
