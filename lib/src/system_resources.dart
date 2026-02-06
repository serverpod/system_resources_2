import 'dart:io';

import 'cpu_monitor.dart';
import 'platform_detector.dart';
import 'memory_monitor.dart';
import 'macos_native.dart';

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

    if (Platform.isWindows) {
      stderr.writeln(
        'WARNING: CPU and memory usage metrics are not supported on Windows.',
      );
      return;
    }

    if (PlatformDetector.detectPlatform() == DetectedPlatform.macOS) {
      MacOsNative.init();
    }
  }

  /// Ensures macOS FFI is initialized. Throws if init() wasn't called.
  static void _ensureMacOsInit() {
    if (!MacOsNative.isInitialized) {
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
  static bool isContainerEnv() => PlatformDetector.isContainerEnv();

  /// Returns the detected cgroup version.
  ///
  /// Returns [CgroupVersion.v2] for modern unified hierarchy,
  /// [CgroupVersion.v1] for legacy hierarchy, or [CgroupVersion.none]
  /// if no cgroups are detected (e.g., on macOS or non-containerized Linux).
  static CgroupVersion cgroupVersion() => PlatformDetector.detectVersion();

  // ---------------------------------------------------------------------------
  // CPU
  // ---------------------------------------------------------------------------

  /// Returns the cgroup usage-micros reader for the current platform,
  /// or `null` if the platform doesn't support cgroup CPU accounting.
  static int Function()? get _usageMicrosReader =>
      switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.linuxCgroupV2 => CpuMonitor.readV2UsageMicros,
        DetectedPlatform.linuxCgroupV1 => CpuMonitor.readV1UsageMicros,
        _ => null,
      };

  /// Returns the cgroup limit-millicores reader for the current platform,
  /// or `null` if the platform doesn't support cgroup CPU limits.
  static int Function()? get _limitMillicoresReader =>
      switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.linuxCgroupV2 => CpuMonitor.readV2LimitMillicores,
        DetectedPlatform.linuxCgroupV1 => CpuMonitor.readV1LimitMillicores,
        _ => null,
      };

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
  static double cpuLoadAvg() => switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.macOS => _macOsCpuLoadAvg(),
        DetectedPlatform.linuxCgroupV2 => CpuMonitor.getLoad(
            CpuMonitor.readV2UsageMicros,
            CpuMonitor.readV2LimitMillicores,
          ),
        DetectedPlatform.linuxCgroupV1 => CpuMonitor.getLoad(
            CpuMonitor.readV1UsageMicros,
            CpuMonitor.readV1LimitMillicores,
          ),
        DetectedPlatform.linuxHost => CpuMonitor.readProcLoadAvg(),
        DetectedPlatform.unsupported => 0.0,
      };

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
    final usageReader = _usageMicrosReader;
    final limitReader = _limitMillicoresReader;
    if (usageReader == null || limitReader == null) return 0.0;
    return CpuMonitor.getLoad(usageReader, limitReader);
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
    final reader = _usageMicrosReader;
    if (reader == null) return 0;
    return CpuMonitor.getUsageMillicores(reader);
  }

  /// Get raw CPU usage in microseconds from cgroup accounting.
  ///
  /// This is the cumulative CPU time consumed by all processes in the
  /// container since it started. Useful for custom delta calculations.
  ///
  /// On non-Linux platforms, always returns 0.
  static int cpuUsageMicros() => switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.linuxCgroupV2 => CpuMonitor.readV2UsageMicros(),
        DetectedPlatform.linuxCgroupV1 => CpuMonitor.readV1UsageMicros(),
        _ => 0,
      };

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
  static double cpuLimitCores() => switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.macOS => _macOsCpuLimitCores(),
        DetectedPlatform.linuxCgroupV2 =>
          CpuMonitor.getLimitCores(CpuMonitor.readV2LimitMillicores),
        DetectedPlatform.linuxCgroupV1 =>
          CpuMonitor.getLimitCores(CpuMonitor.readV1LimitMillicores),
        DetectedPlatform.linuxHost =>
          Platform.numberOfProcessors.toDouble(),
        DetectedPlatform.unsupported =>
          Platform.numberOfProcessors.toDouble(),
      };

  /// Get the CPU limit in millicores (1000m = 1 full CPU core).
  ///
  /// Returns -1 if unlimited or unable to determine.
  ///
  /// On non-Linux platforms, returns host CPU count * 1000.
  static int cpuLimitMillicores() => switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.linuxCgroupV2 => CpuMonitor.readV2LimitMillicores(),
        DetectedPlatform.linuxCgroupV1 => CpuMonitor.readV1LimitMillicores(),
        _ => Platform.numberOfProcessors * 1000,
      };

  // ---------------------------------------------------------------------------
  // Memory
  // ---------------------------------------------------------------------------

  /// Get memory usage as a fraction of the limit.
  ///
  /// Returns a value between 0.0 and 1.0 representing the fraction
  /// of memory currently in use.
  ///
  /// In a container environment, this is relative to the container's
  /// memory limit. On host, this is relative to total system memory.
  static double memUsage() {
    final limit = memoryLimitBytes();
    if (limit <= 0) return 0.0;
    final used = memoryUsedBytes();
    return used / limit;
  }

  /// Get the memory limit in bytes.
  ///
  /// In a container environment, returns the container's memory limit.
  /// On host, returns total system memory.
  static int memoryLimitBytes() => switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.macOS => _macOsMemoryLimitBytes(),
        DetectedPlatform.linuxCgroupV2 => MemoryMonitor.readV2LimitBytes(),
        DetectedPlatform.linuxCgroupV1 => MemoryMonitor.readV1LimitBytes(),
        DetectedPlatform.linuxHost => MemoryMonitor.readProcMemTotal(),
        DetectedPlatform.unsupported => 0,
      };

  /// Get the memory currently used in bytes.
  ///
  /// In a container environment, returns the container's current memory usage.
  /// On host, returns system memory usage (MemTotal - MemAvailable).
  static int memoryUsedBytes() => switch (PlatformDetector.detectPlatform()) {
        DetectedPlatform.macOS => _macOsMemoryUsedBytes(),
        DetectedPlatform.linuxCgroupV2 => MemoryMonitor.readV2UsedBytes(),
        DetectedPlatform.linuxCgroupV1 => MemoryMonitor.readV1UsedBytes(),
        DetectedPlatform.linuxHost => MemoryMonitor.readProcMemUsed(),
        DetectedPlatform.unsupported => 0,
      };

  // ---------------------------------------------------------------------------
  // macOS FFI helpers (guard init)
  // ---------------------------------------------------------------------------

  static double _macOsCpuLoadAvg() {
    _ensureMacOsInit();
    return MacOsNative.cpuLoadAvg();
  }

  static double _macOsCpuLimitCores() {
    _ensureMacOsInit();
    return MacOsNative.cpuLimitCores();
  }

  static int _macOsMemoryLimitBytes() {
    _ensureMacOsInit();
    return MacOsNative.memoryLimitBytes();
  }

  static int _macOsMemoryUsedBytes() {
    _ensureMacOsInit();
    return MacOsNative.memoryUsedBytes();
  }

  // ---------------------------------------------------------------------------
  // State management
  // ---------------------------------------------------------------------------

  /// Clears all cached state. Useful for testing.
  ///
  /// This resets:
  /// - Cached platform detection
  /// - Cached container detection
  /// - CPU usage delta state
  static void clearState() {
    PlatformDetector.clearCache();
    CpuMonitor.clearState();
  }
}
