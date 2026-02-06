import 'dart:ffi';
import 'dart:io';

/// FFI bindings for macOS native library.
///
/// This provides system resource monitoring on macOS using the native
/// libsysres library. On Linux, pure Dart implementations are used instead.

/// Function type definitions for FFI
typedef GetCpuLoadNative = Float Function();
typedef GetCpuLoad = double Function();

typedef GetCpuLimitCoresNative = Float Function();
typedef GetCpuLimitCores = double Function();

typedef GetMemoryUsageNative = Float Function();
typedef GetMemoryUsage = double Function();

typedef GetMemoryLimitBytesNative = Int64 Function();
typedef GetMemoryLimitBytes = int Function();

typedef GetMemoryUsedBytesNative = Int64 Function();
typedef GetMemoryUsedBytes = int Function();

/// macOS native library wrapper for system resources.
class MacOsNative {
  static DynamicLibrary? _lib;
  static GetCpuLoad? _getCpuLoad;
  static GetCpuLimitCores? _getCpuLimitCores;
  static GetMemoryUsage? _getMemoryUsage;
  static GetMemoryLimitBytes? _getMemoryLimitBytes;
  static GetMemoryUsedBytes? _getMemoryUsedBytes;

  static bool _initialized = false;

  /// Returns true if FFI is available and initialized.
  static bool get isInitialized => _initialized;

  /// Initialize the native library for macOS.
  ///
  /// Throws [StateError] if the library cannot be loaded.
  static void init() {
    if (_initialized) return;
    if (!Platform.isMacOS) {
      throw StateError('MacOsNative is only supported on macOS');
    }

    _lib = _loadLibrary();
    _getCpuLoad =
        _lib!.lookupFunction<GetCpuLoadNative, GetCpuLoad>('get_cpu_load');
    _getCpuLimitCores = _lib!
        .lookupFunction<GetCpuLimitCoresNative, GetCpuLimitCores>(
            'get_cpu_limit_cores');
    _getMemoryUsage = _lib!
        .lookupFunction<GetMemoryUsageNative, GetMemoryUsage>('get_memory_usage');
    _getMemoryLimitBytes = _lib!.lookupFunction<GetMemoryLimitBytesNative,
        GetMemoryLimitBytes>('get_memory_limit_bytes');
    _getMemoryUsedBytes = _lib!.lookupFunction<GetMemoryUsedBytesNative,
        GetMemoryUsedBytes>('get_memory_used_bytes');

    _initialized = true;
  }

  /// Get the library filename for macOS.
  static String _getLibraryPath() {
    final arch = _getArch();
    return 'libsysres-darwin-$arch.dylib';
  }

  /// Get normalized architecture name for macOS.
  static String _getArch() {
    // Check environment variable override
    final envArch =
        Platform.environment['ARCH'] ?? Platform.environment['GOARCH'];

    if (envArch != null) {
      final normalized = envArch.toLowerCase();
      if (normalized == 'arm64' || normalized == 'aarch64') {
        return 'arm64';
      }
      if (normalized == 'amd64' || normalized == 'x86_64') {
        return 'x86_64';
      }
    }

    // Use ABI-based detection
    final abi = Abi.current();
    switch (abi) {
      case Abi.macosArm64:
        return 'arm64';
      case Abi.macosX64:
        return 'x86_64';
      default:
        throw UnsupportedError('Unsupported macOS architecture: $abi');
    }
  }

  /// Try to find and load the library from various locations.
  static DynamicLibrary _loadLibrary() {
    final libName = _getLibraryPath();
    final locations = <String>[];
    final errors = <String>[];

    // Get the script/executable directory
    final scriptUri = Platform.script;
    if (scriptUri.scheme == 'file') {
      final scriptDir = File(scriptUri.toFilePath()).parent.path;
      locations.add('$scriptDir/$libName');
      locations.add('$scriptDir/lib/build/$libName');
    }

    // Check relative to current directory
    locations.add('lib/build/$libName');
    locations.add('build/$libName');
    locations.add(libName);

    // Check in package cache (for pub dependencies)
    final homeDir =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (homeDir.isNotEmpty) {
      final pubCachePath =
          Platform.environment['PUB_CACHE'] ?? '$homeDir/.pub-cache';
      locations.add(
          '$pubCachePath/hosted/pub.dev/system_resources_2/lib/build/$libName');
    }

    // Try each location
    for (final path in locations) {
      try {
        return DynamicLibrary.open(path);
      } catch (e) {
        errors.add('$path: $e');
      }
    }

    // Last resort: try to load from system path
    try {
      return DynamicLibrary.open(libName);
    } catch (e) {
      errors.add('system path ($libName): $e');

      throw StateError(
        'Could not load native library: $libName\n\n'
        'Searched locations:\n${locations.map((l) => '  - $l').join('\n')}\n\n'
        'Errors:\n${errors.map((e) => '  $e').join('\n')}',
      );
    }
  }

  /// Get CPU load average normalized by CPU cores.
  static double cpuLoadAvg() {
    _ensureInitialized();
    return _getCpuLoad!();
  }

  /// Get CPU limit in cores.
  static double cpuLimitCores() {
    _ensureInitialized();
    return _getCpuLimitCores!();
  }

  /// Get memory usage as fraction of limit.
  static double memUsage() {
    _ensureInitialized();
    return _getMemoryUsage!();
  }

  /// Get memory limit in bytes.
  static int memoryLimitBytes() {
    _ensureInitialized();
    return _getMemoryLimitBytes!();
  }

  /// Get memory used in bytes.
  static int memoryUsedBytes() {
    _ensureInitialized();
    return _getMemoryUsedBytes!();
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'MacOsNative not initialized. Call SystemResources.init() first.',
      );
    }
  }
}
