import 'dart:ffi' as ffi;

/// Native binding for get_cpu_load from libsysres
@ffi.Native<ffi.Float Function()>(
  symbol: 'get_cpu_load',
  assetId: 'package:system_resources_2/libsysres',
)
external double _getCpuLoad();

/// Native binding for get_memory_usage from libsysres
@ffi.Native<ffi.Float Function()>(
  symbol: 'get_memory_usage',
  assetId: 'package:system_resources_2/libsysres',
)
external double _getMemoryUsage();

/// Provides easy access to system resources (CPU load, memory usage).
///
/// With native assets, there's no need to call init() before using
/// the methods. The native library is automatically linked at build time.
class SystemResources {
  /// Deprecated: No longer needed with native assets.
  /// Kept for backward compatibility - calling this is now a no-op.
  @Deprecated('init() is no longer required with native assets')
  static Future<void> init() async {
    // No-op: native assets handles library loading automatically
  }

  /// Get system CPU load average.
  ///
  /// Returns a value representing the normalized CPU load.
  /// A value of 1.0 means all CPU cores are fully utilized.
  /// Values can exceed 1.0 if the system is overloaded.
  static double cpuLoadAvg() {
    return _getCpuLoad();
  }

  /// Get system memory currently used.
  ///
  /// Returns a value between 0.0 and 1.0 representing the fraction
  /// of memory currently in use.
  static double memUsage() {
    return _getMemoryUsage();
  }
}
