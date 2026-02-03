import 'dart:io';

import 'cgroup_detector.dart';

/// Memory monitoring using cgroup metrics.
///
/// Reads memory usage and limits from cgroup v1/v2 files,
/// with fallback to /proc/meminfo for host environments.
class CgroupMemory {
  /// Gets the memory limit in bytes.
  ///
  /// For cgroup v2: reads `/sys/fs/cgroup/memory.max`
  /// For cgroup v1: reads `/sys/fs/cgroup/memory/memory.limit_in_bytes`
  /// Fallback: reads MemTotal from `/proc/meminfo`
  ///
  /// Returns the memory limit, or total system memory if not in a container.
  static int getLimitBytes() {
    final version = CgroupDetector.detectVersion();

    if (version == CgroupVersion.v2) {
      final limit = _readCgroupV2Limit();
      if (limit > 0) return limit;
    } else if (version == CgroupVersion.v1) {
      final limit = _readCgroupV1Limit();
      if (limit > 0) return limit;
    }

    // Fallback to /proc/meminfo
    return _readProcMemTotal();
  }

  /// Reads memory limit from cgroup v2.
  static int _readCgroupV2Limit() {
    try {
      final content =
          File(CgroupDetector.cgroupV2MemoryMax).readAsStringSync().trim();
      if (content == 'max') {
        // Unlimited - fall back to system memory
        return _readProcMemTotal();
      }
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Reads memory limit from cgroup v1.
  static int _readCgroupV1Limit() {
    try {
      final content =
          File(CgroupDetector.cgroupV1MemoryLimit).readAsStringSync().trim();
      final limit = int.tryParse(content);
      if (limit != null) {
        // Very large values indicate no limit
        if (limit > 9000000000000000000) {
          return _readProcMemTotal();
        }
        return limit;
      }
    } catch (_) {}
    return 0;
  }

  /// Reads MemTotal from /proc/meminfo.
  static int _readProcMemTotal() {
    try {
      final content = File(CgroupDetector.procMeminfo).readAsStringSync();
      for (final line in content.split('\n')) {
        if (line.startsWith('MemTotal:')) {
          // Format: "MemTotal:       16384000 kB"
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final kb = int.tryParse(parts[1]);
            if (kb != null) {
              return kb * 1024; // Convert to bytes
            }
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Gets the memory currently used in bytes.
  ///
  /// For cgroup v2: reads `/sys/fs/cgroup/memory.current`
  /// For cgroup v1: reads `/sys/fs/cgroup/memory/memory.usage_in_bytes`
  /// Fallback: calculates from /proc/meminfo (MemTotal - MemAvailable)
  ///
  /// Returns current memory usage in bytes.
  static int getUsedBytes() {
    final version = CgroupDetector.detectVersion();

    if (version == CgroupVersion.v2) {
      final used = _readCgroupV2Used();
      if (used > 0) return used;
    } else if (version == CgroupVersion.v1) {
      final used = _readCgroupV1Used();
      if (used > 0) return used;
    }

    // Fallback to /proc/meminfo calculation
    return _readProcMemUsed();
  }

  /// Reads memory usage from cgroup v2.
  static int _readCgroupV2Used() {
    try {
      final content =
          File(CgroupDetector.cgroupV2MemoryCurrent).readAsStringSync().trim();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Reads memory usage from cgroup v1.
  static int _readCgroupV1Used() {
    try {
      final content =
          File(CgroupDetector.cgroupV1MemoryUsage).readAsStringSync().trim();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Calculates memory used from /proc/meminfo.
  static int _readProcMemUsed() {
    try {
      final content = File(CgroupDetector.procMeminfo).readAsStringSync();
      int? memTotal;
      int? memAvailable;

      for (final line in content.split('\n')) {
        if (line.startsWith('MemTotal:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            memTotal = int.tryParse(parts[1]);
          }
        } else if (line.startsWith('MemAvailable:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            memAvailable = int.tryParse(parts[1]);
          }
        }
      }

      if (memTotal != null && memAvailable != null) {
        return (memTotal - memAvailable) * 1024; // Convert to bytes
      }
    } catch (_) {}
    return 0;
  }

  /// Gets memory usage as a fraction of the limit.
  ///
  /// Returns a value between 0.0 and 1.0 representing the fraction
  /// of memory currently in use.
  static double getUsage() {
    final limit = getLimitBytes();
    if (limit <= 0) return 0.0;

    final used = getUsedBytes();
    return used / limit;
  }
}
