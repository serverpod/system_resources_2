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
class PlatformDetector {
  static DetectedPlatform? _cachedPlatform;
  static bool? _cachedIsContainer;
  static String? _cachedCgroupDir;

  static const cgroupV2Mount = '/sys/fs/cgroup';

  /// Resolved from the process's actual cgroup dir (see [resolveCgroupDir]).
  static String get cgroupV2CpuStat => '${resolveCgroupDir()}/cpu.stat';
  static String get cgroupV2CpuMax => '${resolveCgroupDir()}/cpu.max';
  static String get cgroupV2MemoryCurrent =>
      '${resolveCgroupDir()}/memory.current';
  static String get cgroupV2MemoryMax => '${resolveCgroupDir()}/memory.max';

  /// Root-level path for initial v2 detection only (always exists on v2).
  static const _cgroupV2RootCpuStat = '/sys/fs/cgroup/cpu.stat';

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

  static const procMeminfo = '/proc/meminfo';
  static const procStat = '/proc/stat';
  static const procLoadAvg = '/proc/loadavg';

  static const procSelfCgroup = '/proc/self/cgroup';

  static DetectedPlatform detectPlatform() {
    if (_cachedPlatform != null) return _cachedPlatform!;

    if (Platform.isMacOS) {
      _cachedPlatform = DetectedPlatform.macOS;
    } else if (Platform.isLinux) {
      if (File(_cgroupV2RootCpuStat).existsSync()) {
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

  static CgroupVersion detectVersion() => switch (detectPlatform()) {
        DetectedPlatform.linuxCgroupV2 => CgroupVersion.v2,
        DetectedPlatform.linuxCgroupV1 => CgroupVersion.v1,
        _ => CgroupVersion.none,
      };

  static bool isContainerEnv() {
    if (_cachedIsContainer != null) return _cachedIsContainer!;

    _cachedIsContainer = switch (detectPlatform()) {
      DetectedPlatform.linuxCgroupV2 => _detectContainerV2(),
      DetectedPlatform.linuxCgroupV1 => _detectContainerV1(),
      _ => false,
    };

    return _cachedIsContainer!;
  }

  /// "max" = unlimited (host), numeric = container limit.
  static bool _detectContainerV2() {
    try {
      final content = File(cgroupV2MemoryMax).readAsStringSync().trim();
      return content != 'max';
    } catch (_) {
      return false;
    }
  }

  /// Values > 9e18 indicate no limit (host).
  static bool _detectContainerV1() {
    try {
      final limit =
          int.tryParse(File(cgroupV1MemoryLimit).readAsStringSync().trim());
      return limit != null && limit < 9000000000000000000;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the process's cgroup v2 directory from `/proc/self/cgroup`.
  ///
  /// In containers: `0::/` -> `/sys/fs/cgroup`.
  /// On hosts: `0::/user.slice/.../session.scope` -> full path where
  /// memory controller files reside.
  ///
  /// See `docs/cgroup-path-resolution.md` for background.
  static String resolveCgroupDir() {
    if (_cachedCgroupDir != null) return _cachedCgroupDir!;

    _cachedCgroupDir = _readCgroupDirFromProc() ?? cgroupV2Mount;
    return _cachedCgroupDir!;
  }

  /// Parses `/proc/self/cgroup` for the v2 entry (`0::$PATH`).
  static String? _readCgroupDirFromProc() {
    try {
      final content = File(procSelfCgroup).readAsStringSync();
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // Format: hierarchy-ID:controller-list:cgroup-path
        final parts = trimmed.split(':');
        if (parts.length != 3) continue;

        if (parts[0] == '0' && parts[1].isEmpty) {
          final cgroupPath = parts[2];
          if (cgroupPath == '/') return cgroupV2Mount;
          final normalized = cgroupPath.endsWith('/')
              ? cgroupPath.substring(0, cgroupPath.length - 1)
              : cgroupPath;
          return '$cgroupV2Mount$normalized';
        }
      }
    } catch (_) {}
    return null;
  }

  static void clearCache() {
    _cachedPlatform = null;
    _cachedIsContainer = null;
    _cachedCgroupDir = null;
  }
}
