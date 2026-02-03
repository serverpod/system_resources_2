import 'dart:io';

import 'cgroup_cpu.dart';
import 'cgroup_detector.dart';
import 'cgroup_memory.dart';
import 'macos_ffi.dart';

/// Provides easy access to system resources (CPU load, memory usage).
///
/// This library is **container-aware** and automatically detects container
/// environments using cgroup v1/v2. When running inside a container, resource
/// usage is calculated relative to container limits rather than host resources.
///
/// ## Key Features
///
/// - **Hybrid implementation** - Pure Dart on Linux, FFI on macOS
/// - **gVisor compatible** - Works in gVisor environments (unlike getloadavg)
/// - **Cgroup v1/v2 support** - Automatically detects and uses appropriate paths
/// - **Graceful fallbacks** - Falls back to /proc for non-container environments
/// - **Serverpod compatible** - Drop-in replacement for system_resources package
///
/// ## CPU Monitoring
///
/// CPU monitoring uses cgroup accounting (`cpu.stat` or `cpuacct.usage`) to track
/// actual CPU time consumed. This differs from load average in that it:
/// - Tracks ALL processes in the container (not just the calling process)
/// - Works in gVisor (which doesn't support getloadavg)
/// - Measures actual CPU consumption, not queue depth
///
/// Note: [cpuLoad] requires two calls to calculate a delta. The first call
/// returns 0.0 as there's no previous reading to compare against.
///
/// ## Memory Monitoring
///
/// Memory monitoring reads from cgroup memory controller files, with fallback
/// to `/proc/meminfo` for non-container environments.
///
/// ## Example
///
/// ```dart
/// // Initialize (required for Serverpod compatibility, no-op on Linux)
/// await SystemResources.init();
///
/// // Check if running in a container
/// print('Container: ${SystemResources.isContainerEnv()}');
///
/// // Get CPU metrics
/// print('CPU limit: ${SystemResources.cpuLimitCores()} cores');
/// print('CPU load: ${(SystemResources.cpuLoadAvg() * 100).toStringAsFixed(1)}%');
///
/// // Get memory metrics
/// print('Memory used: ${SystemResources.memoryUsedBytes() ~/ 1024 ~/ 1024} MB');
/// print('Memory limit: ${SystemResources.memoryLimitBytes() ~/ 1024 ~/ 1024} MB');
/// print('Memory usage: ${(SystemResources.memUsage() * 100).toStringAsFixed(1)}%');
/// ```
class SystemResources {
  static bool _initialized = false;

  /// Initialize the library.
  ///
  /// This method exists for API compatibility with Serverpod and the original
  /// system_resources package. On Linux, this is a no-op since pure Dart
  /// implementation requires no initialization.
  ///
  /// On macOS, this loads the native library for FFI calls.
  ///
  /// It's safe to call this method multiple times.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // On macOS: initialize FFI
    if (Platform.isMacOS) {
      MacOsFfi.init();
    }
    // On Linux: no-op, pure Dart implementation
  }

  /// Ensures macOS FFI is initialized. Throws if init() wasn't called.
  static void _ensureMacOsInit() {
    if (!MacOsFfi.isInitialized) {
      throw StateError(
        'SystemResources not initialized. Call SystemResources.init() first.',
      );
    }
  }
  /// Returns `true` if running in a detected container environment.
  ///
  /// Container detection is based on the presence of cgroup memory limits.
  /// Returns `false` on non-Linux platforms or when running on a host
  /// without container limits.
  static bool isContainerEnv() {
    return CgroupDetector.isContainerEnv();
  }

  /// Returns the detected cgroup version.
  ///
  /// Returns [CgroupVersion.v2] for modern unified hierarchy,
  /// [CgroupVersion.v1] for legacy hierarchy, or [CgroupVersion.none]
  /// if no cgroups are detected (e.g., on macOS or non-containerized Linux).
  static CgroupVersion cgroupVersion() {
    return CgroupDetector.detectVersion();
  }

  /// Get CPU load average normalized by CPU limit/count.
  ///
  /// This is the primary CPU monitoring method, compatible with Serverpod
  /// and the original system_resources package.
  ///
  /// **Behavior by environment:**
  /// - **Container (cgroups)**: Uses cgroup CPU accounting. First call
  ///   initializes tracking and returns 0.0; subsequent calls return
  ///   actual load based on CPU time delta.
  /// - **Linux host**: Reads 1-minute load average from `/proc/loadavg`
  ///   and normalizes by CPU count.
  /// - **macOS**: Uses native FFI (requires [init()] to be called first).
  ///
  /// Returns a value where 1.0 means 100% CPU utilization.
  static double cpuLoadAvg() {
    if (Platform.isMacOS) {
      _ensureMacOsInit();
      return MacOsFfi.cpuLoadAvg();
    }
    if (Platform.isLinux) {
      return CgroupCpu.getLoadAvg();
    }
    return 0.0;
  }

  /// Get CPU load as a fraction of the limit (cgroup-based only).
  ///
  /// Returns a value where 1.0 means 100% of CPU limit is being used.
  /// Values can exceed 1.0 if usage exceeds the limit.
  ///
  /// **Important:** This method requires delta calculation between calls.
  /// The first call returns 0.0. For accurate readings, wait at least
  /// 100ms between calls.
  ///
  /// On non-Linux platforms or hosts without cgroups, returns 0.0.
  /// Use [cpuLoadAvg()] for broader compatibility.
  static double cpuLoad() {
    if (!Platform.isLinux) return 0.0;
    return CgroupCpu.getLoad();
  }

  /// Get CPU usage in millicores (1000m = 1 full CPU core).
  ///
  /// This measures actual CPU time consumed since the last call.
  /// For example, 500m means half a CPU core is being used.
  ///
  /// **Important:** This method requires delta calculation between calls.
  /// The first call returns 0. For accurate readings, wait at least
  /// 100ms between calls.
  ///
  /// On non-Linux platforms, always returns 0.
  static int cpuUsageMillicores() {
    if (!Platform.isLinux) return 0;
    return CgroupCpu.getUsageMillicores();
  }

  /// Get raw CPU usage in microseconds from cgroup accounting.
  ///
  /// This is the cumulative CPU time consumed by all processes in the
  /// container since it started. Useful for custom delta calculations.
  ///
  /// On non-Linux platforms, always returns 0.
  static int cpuUsageMicros() {
    if (!Platform.isLinux) return 0;
    return CgroupCpu.getUsageMicros();
  }

  /// Get the CPU limit in cores.
  ///
  /// In a container environment, returns the container's CPU limit
  /// (e.g., 0.5 for 500m, 2.0 for 2 cores).
  ///
  /// If no limit is set, returns the host CPU count.
  ///
  /// The `SYSRES_CPU_CORES` environment variable can be used to override
  /// this value, which is useful for gVisor environments that don't
  /// expose cgroup limits.
  static double cpuLimitCores() {
    if (Platform.isMacOS) {
      _ensureMacOsInit();
      return MacOsFfi.cpuLimitCores();
    }
    if (Platform.isLinux) {
      return CgroupCpu.getLimitCores();
    }
    return Platform.numberOfProcessors.toDouble();
  }

  /// Get the CPU limit in millicores (1000m = 1 full CPU core).
  ///
  /// Returns -1 if unlimited or unable to determine.
  ///
  /// On non-Linux platforms, returns host CPU count * 1000.
  static int cpuLimitMillicores() {
    if (!Platform.isLinux) {
      return Platform.numberOfProcessors * 1000;
    }
    return CgroupCpu.getLimitMillicores();
  }

  /// Get memory usage as a fraction of the limit.
  ///
  /// Returns a value between 0.0 and 1.0 representing the fraction
  /// of memory currently in use.
  ///
  /// In a container environment, this is relative to the container's
  /// memory limit. On host, this is relative to total system memory.
  static double memUsage() {
    if (Platform.isMacOS) {
      _ensureMacOsInit();
      return MacOsFfi.memUsage();
    }
    if (Platform.isLinux) {
      return CgroupMemory.getUsage();
    }
    return 0.0;
  }

  /// Get the memory limit in bytes.
  ///
  /// In a container environment, returns the container's memory limit.
  /// On host, returns total system memory.
  static int memoryLimitBytes() {
    if (Platform.isMacOS) {
      _ensureMacOsInit();
      return MacOsFfi.memoryLimitBytes();
    }
    if (Platform.isLinux) {
      return CgroupMemory.getLimitBytes();
    }
    return 0;
  }

  /// Get the memory currently used in bytes.
  ///
  /// In a container environment, returns the container's current memory usage.
  /// On host, returns system memory usage (MemTotal - MemAvailable).
  static int memoryUsedBytes() {
    if (Platform.isMacOS) {
      _ensureMacOsInit();
      return MacOsFfi.memoryUsedBytes();
    }
    if (Platform.isLinux) {
      return CgroupMemory.getUsedBytes();
    }
    return 0;
  }

  /// Clears all cached state. Useful for testing.
  ///
  /// This resets:
  /// - Cached cgroup version detection
  /// - Cached container detection
  /// - CPU usage delta state
  static void clearState() {
    CgroupDetector.clearCache();
    CgroupCpu.clearState();
  }
}
