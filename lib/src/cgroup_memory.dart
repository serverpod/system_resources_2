import 'dart:io';

import 'cgroup_detector.dart';

/// Memory monitoring using cgroup metrics.
///
/// Provides per-cgroup-version reader methods that are called directly
/// from `SystemResources` via a flat switch on [DetectedPlatform].
///
/// Falls back to `/proc/meminfo` for host environments.
class CgroupMemory {
  // ---------------------------------------------------------------------------
  // Memory limit readers (bytes)
  // ---------------------------------------------------------------------------

  /// Reads memory limit from cgroup v2.
  ///
  /// Reads `/sys/fs/cgroup/memory.max`. Returns the numeric limit in bytes,
  /// or falls back to `/proc/meminfo` MemTotal if the value is `"max"`
  /// (unlimited).
  /// Returns 0 if unable to read.
  static int readV2LimitBytes() {
    try {
      final content =
          File(CgroupDetector.cgroupV2MemoryMax).readAsStringSync().trim();
      if (content == 'max') {
        // Unlimited - fall back to system memory
        return readProcMemTotal();
      }
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Reads memory limit from cgroup v1.
  ///
  /// Reads `/sys/fs/cgroup/memory/memory.limit_in_bytes`. Very large values
  /// (>9e18) indicate no limit, in which case falls back to MemTotal.
  /// Returns 0 if unable to read.
  static int readV1LimitBytes() {
    try {
      final content =
          File(CgroupDetector.cgroupV1MemoryLimit).readAsStringSync().trim();
      final limit = int.tryParse(content);
      if (limit != null) {
        // Very large values indicate no limit
        if (limit > 9000000000000000000) {
          return readProcMemTotal();
        }
        return limit;
      }
    } catch (_) {}
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Memory used readers (bytes)
  // ---------------------------------------------------------------------------

  /// Reads memory usage from cgroup v2.
  ///
  /// Reads `/sys/fs/cgroup/memory.current`.
  /// Returns 0 if unable to read.
  static int readV2UsedBytes() {
    try {
      final content =
          File(CgroupDetector.cgroupV2MemoryCurrent).readAsStringSync().trim();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Reads memory usage from cgroup v1.
  ///
  /// Reads `/sys/fs/cgroup/memory/memory.usage_in_bytes`.
  /// Returns 0 if unable to read.
  static int readV1UsedBytes() {
    try {
      final content =
          File(CgroupDetector.cgroupV1MemoryUsage).readAsStringSync().trim();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return 0;
  }

  // ---------------------------------------------------------------------------
  // /proc fallback
  // ---------------------------------------------------------------------------

  /// Reads MemTotal from `/proc/meminfo` in bytes.
  static int readProcMemTotal() {
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

  /// Calculates memory used from `/proc/meminfo` (MemTotal - MemAvailable).
  static int readProcMemUsed() {
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
}
