import 'dart:ffi';
import 'dart:io';

/// Function type for CPU load
typedef GetCpuLoadNative = Float Function();
typedef GetCpuLoad = double Function();

/// Function type for memory usage
typedef GetMemoryUsageNative = Float Function();
typedef GetMemoryUsage = double Function();

/// The loaded native library
DynamicLibrary? _lib;

/// Native function bindings
GetCpuLoad? _getCpuLoad;
GetMemoryUsage? _getMemoryUsage;

/// Get the library filename for the current platform
String _getLibraryPath() {
  final os = Platform.operatingSystem;
  final arch = _getArch();

  if (Platform.isMacOS) {
    return 'libsysres-darwin-$arch.dylib';
  } else if (Platform.isLinux) {
    return 'libsysres-linux-$arch.so';
  } else {
    throw UnsupportedError('Unsupported platform: $os');
  }
}

/// Get normalized architecture name using Abi.current()
String _getArch() {
  final abi = Abi.current();
  switch (abi) {
    case Abi.macosArm64:
      return 'arm64';
    case Abi.macosX64:
      return 'x86_64';
    case Abi.linuxArm64:
      return 'aarch64';
    case Abi.linuxX64:
      return 'x86_64';
    case Abi.linuxIA32:
      return 'i686';
    case Abi.linuxArm:
      return 'armv7l';
    default:
      throw UnsupportedError('Unsupported platform: $abi');
  }
}

/// Try to find and load the library from various locations
DynamicLibrary _loadLibrary() {
  final libName = _getLibraryPath();
  final locations = <String>[];

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
  final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (homeDir.isNotEmpty) {
    // Look in pub cache
    final pubCachePath = Platform.environment['PUB_CACHE'] ?? '$homeDir/.pub-cache';
    locations.add('$pubCachePath/hosted/pub.dev/system_resources_2/lib/build/$libName');
  }

  // Try each location
  for (final path in locations) {
    try {
      // Handle glob patterns
      if (path.contains('*')) {
        final dir = Directory(path.substring(0, path.lastIndexOf('*')).replaceAll('*', ''));
        if (dir.existsSync()) {
          for (final entity in dir.parent.listSync()) {
            if (entity is Directory && entity.path.contains('system_resources_2')) {
              final libPath = '${entity.path}/lib/build/$libName';
              if (File(libPath).existsSync()) {
                return DynamicLibrary.open(libPath);
              }
            }
          }
        }
        continue;
      }

      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    } catch (_) {
      // Try next location
    }
  }

  // Last resort: try to load from system path
  try {
    return DynamicLibrary.open(libName);
  } catch (e) {
    throw StateError(
      'Could not find $libName. '
      'Searched in: ${locations.join(", ")}. '
      'Make sure the library is in one of these locations.',
    );
  }
}

/// Initialize the library bindings
void _ensureInitialized() {
  if (_lib != null) return;

  _lib = _loadLibrary();
  _getCpuLoad = _lib!.lookupFunction<GetCpuLoadNative, GetCpuLoad>('get_cpu_load');
  _getMemoryUsage = _lib!.lookupFunction<GetMemoryUsageNative, GetMemoryUsage>('get_memory_usage');
}

/// Provides easy access to system resources (CPU load, memory usage).
///
/// The library automatically loads pre-compiled binaries from the package.
/// No initialization is required - the library is loaded on first use.
class SystemResources {
  /// Initialize the native library.
  ///
  /// This is called automatically on first use, but can be called explicitly
  /// to catch any loading errors early.
  static Future<void> init() async {
    _ensureInitialized();
  }

  /// Get system CPU load average.
  ///
  /// Returns a value representing the normalized CPU load.
  /// A value of 1.0 means all CPU cores are fully utilized.
  /// Values can exceed 1.0 if the system is overloaded.
  static double cpuLoadAvg() {
    _ensureInitialized();
    return _getCpuLoad!();
  }

  /// Get system memory currently used.
  ///
  /// Returns a value between 0.0 and 1.0 representing the fraction
  /// of memory currently in use.
  static double memUsage() {
    _ensureInitialized();
    return _getMemoryUsage!();
  }
}
