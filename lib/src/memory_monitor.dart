import 'dart:io';

import 'platform_detector.dart';

/// Memory monitoring via cgroup files, with `/proc/meminfo` fallback.
class MemoryMonitor {
  /// Falls back to `/proc/meminfo` when cgroup file is "max" or unreadable.
  static int readV2LimitBytes() {
    try {
      final content =
          File(PlatformDetector.cgroupV2MemoryMax).readAsStringSync().trim();
      if (content == 'max') return readProcMemTotal();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return readProcMemTotal();
  }

  /// Values > 9e18 mean unlimited in cgroup v1.
  static int readV1LimitBytes() {
    try {
      final content =
          File(PlatformDetector.cgroupV1MemoryLimit).readAsStringSync().trim();
      final limit = int.tryParse(content);
      if (limit != null) {
        if (limit > 9000000000000000000) return readProcMemTotal();
        return limit;
      }
    } catch (_) {}
    return readProcMemTotal();
  }

  static int readV2UsedBytes() {
    try {
      final content =
          File(PlatformDetector.cgroupV2MemoryCurrent).readAsStringSync().trim();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return readProcMemUsed();
  }

  static int readV1UsedBytes() {
    try {
      final content =
          File(PlatformDetector.cgroupV1MemoryUsage).readAsStringSync().trim();
      return int.tryParse(content) ?? 0;
    } catch (_) {}
    return readProcMemUsed();
  }

  static int readProcMemTotal() {
    try {
      final content = File(PlatformDetector.procMeminfo).readAsStringSync();
      for (final line in content.split('\n')) {
        if (line.startsWith('MemTotal:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final kb = int.tryParse(parts[1]);
            if (kb != null) return kb * 1024;
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  static int readProcMemUsed() {
    try {
      final content = File(PlatformDetector.procMeminfo).readAsStringSync();
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
