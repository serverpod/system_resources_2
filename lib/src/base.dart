import 'dart:ffi';
import 'dart:io';

/// Function type for CPU load
typedef GetCpuLoadNative = Float Function();
typedef GetCpuLoad = double Function();

/// Function type for CPU limit cores
typedef GetCpuLimitCoresNative = Float Function();
typedef GetCpuLimitCores = double Function();

/// Function type for memory usage
typedef GetMemoryUsageNative = Float Function();
typedef GetMemoryUsage = double Function();

/// Function type for memory limit bytes
typedef GetMemoryLimitBytesNative = Int64 Function();
typedef GetMemoryLimitBytes = int Function();

/// Function type for memory used bytes
typedef GetMemoryUsedBytesNative = Int64 Function();
typedef GetMemoryUsedBytes = int Function();

/// Function type for container detection
typedef IsContainerEnvNative = Int32 Function();
typedef IsContainerEnv = int Function();

/// The loaded native library
DynamicLibrary? _lib;

/// Native function bindings
GetCpuLoad? _getCpuLoad;
GetCpuLimitCores? _getCpuLimitCores;
GetMemoryUsage? _getMemoryUsage;
GetMemoryLimitBytes? _getMemoryLimitBytes;
GetMemoryUsedBytes? _getMemoryUsedBytes;
IsContainerEnv? _isContainerEnv;

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
/// Checks environment variables first (for cross-compilation scenarios)
/// Also checks available library files as a fallback
String _getArch() {
  // Check environment variables first (GCC-compatible: ARCH, GOARCH)
  // This allows overriding the ABI-based detection for cross-compilation scenarios
  if (Platform.isLinux) {
    final envArch = Platform.environment['ARCH'] ?? 
                    Platform.environment['GOARCH'];
    
    if (envArch != null) {
      final normalized = envArch.toLowerCase();
      // Map common environment variable values to our architecture names
      if (normalized == 'amd64' || normalized == 'x86_64') {
        return 'x86_64';
      }
      if (normalized == 'arm64' || normalized == 'aarch64') {
        return 'aarch64';
      }
      if (normalized == 'arm' || normalized == 'armv7' || normalized == 'armv7l') {
        return 'armv7l';
      }
      if (normalized == 'i386' || normalized == 'i686' || normalized == '386') {
        return 'i686';
      }
      // If it's already in our format, return as-is
      if (normalized == 'x86_64' || normalized == 'aarch64' || normalized == 'armv7l' || normalized == 'i686') {
        return normalized;
      }
    }
    
    // Check what library files exist in lib/build/ as a fallback
    // This helps when cross-compiling (e.g., i686 on x86_64 host)
    // Check executable directory and relative paths (same approach as _loadLibrary)
    try {
      final possibleDirs = <Directory>[];
      
      // Check executable directory
      try {
        final executableDir = File(Platform.resolvedExecutable).parent;
        possibleDirs.add(Directory('${executableDir.path}/lib/build'));
      } catch (_) {
        // Ignore if executable path not available
      }
      
      // Check script directory
      final scriptUri = Platform.script;
      if (scriptUri.scheme == 'file') {
        try {
          final scriptDir = File(scriptUri.toFilePath()).parent;
          possibleDirs.add(Directory('${scriptDir.path}/lib/build'));
        } catch (_) {
          // Ignore if script path not available
        }
      }
      
      // Also check relative paths from current working directory
      possibleDirs.addAll([
        Directory('lib/build'),
        Directory('../lib/build'),
        Directory('../../lib/build'),
      ]);
      
      for (final libBuildDir in possibleDirs) {
        if (libBuildDir.existsSync()) {
          final libFiles = libBuildDir.listSync()
              .whereType<File>()
              .where((f) => f.path.contains('libsysres-linux-') && f.path.endsWith('.so'))
              .map((f) => f.path)
              .toList();
          
          // If only one library exists, use that architecture
          if (libFiles.length == 1) {
            final match = RegExp(r'libsysres-linux-([^.]+)\.so').firstMatch(libFiles.first);
            if (match != null) {
              return match.group(1)!;
            }
          }
        }
      }
    } catch (_) {
      // Ignore errors and fall through to ABI detection
    }
  } else if (Platform.isMacOS) {
    final envArch = Platform.environment['ARCH'] ?? 
                    Platform.environment['GOARCH'];
    
    if (envArch != null) {
      final normalized = envArch.toLowerCase();
      if (normalized == 'arm64' || normalized == 'aarch64') {
        return 'arm64';
      }
      if (normalized == 'amd64' || normalized == 'x86_64') {
        return 'x86_64';
      }
    }
  }
  
  // Fallback to ABI-based detection
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
  _getCpuLoad =
      _lib!.lookupFunction<GetCpuLoadNative, GetCpuLoad>('get_cpu_load');
  _getCpuLimitCores = _lib!
      .lookupFunction<GetCpuLimitCoresNative, GetCpuLimitCores>('get_cpu_limit_cores');
  _getMemoryUsage = _lib!
      .lookupFunction<GetMemoryUsageNative, GetMemoryUsage>('get_memory_usage');
  _getMemoryLimitBytes = _lib!.lookupFunction<GetMemoryLimitBytesNative,
      GetMemoryLimitBytes>('get_memory_limit_bytes');
  _getMemoryUsedBytes = _lib!.lookupFunction<GetMemoryUsedBytesNative,
      GetMemoryUsedBytes>('get_memory_used_bytes');
  _isContainerEnv = _lib!
      .lookupFunction<IsContainerEnvNative, IsContainerEnv>('is_container_env');
}

/// Provides easy access to system resources (CPU load, memory usage).
///
/// This library is **container-aware** and automatically detects container
/// environments using cgroups v2. When running inside a container, resource
/// usage is calculated relative to container limits rather than host resources.
///
/// **Requirements for container detection:**
/// - Kubernetes 1.25+ (cgroups v2 is default)
/// - Non-k8s environments must have cgroups v2 enabled
///
/// **Note:** CPU monitoring is not supported in gVisor environments.
/// Memory monitoring works correctly in gVisor. See docs/GVISOR.md for details.
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

  /// Returns `true` if running in a detected container environment.
  ///
  /// Container detection is based on the presence of cgroups v2 memory limits.
  /// Returns `false` on macOS (no native container support) or when running
  /// on a host without container limits.
  static bool isContainerEnv() {
    _ensureInitialized();
    return _isContainerEnv!() != 0;
  }

  /// Get CPU load average normalized by available CPU cores.
  ///
  /// In a container environment, this is normalized by the container's CPU
  /// limit (from cgroups v2). On host, this is normalized by the total number
  /// of CPU cores.
  ///
  /// Returns a value representing the normalized CPU load.
  /// A value of 1.0 means all available CPU cores are fully utilized.
  /// Values can exceed 1.0 if the system is overloaded.
  ///
  /// **Note:** Not supported in gVisor - always returns 0. Use external
  /// monitoring solutions for CPU usage in gVisor environments.
  static double cpuLoadAvg() {
    _ensureInitialized();
    return _getCpuLoad!();
  }

  /// Get the CPU limit in cores.
  ///
  /// In a container environment, returns the container's CPU limit.
  /// On host, returns the total number of CPU cores.
  ///
  /// **Note:** In gVisor environments, returns host cores (gVisor does not
  /// expose cgroups).
  static double cpuLimitCores() {
    _ensureInitialized();
    return _getCpuLimitCores!();
  }

  /// Get memory usage as a fraction of the limit.
  ///
  /// In a container environment, this is calculated relative to the
  /// container's memory limit (from cgroups v2).
  /// On host, this is calculated relative to total system memory.
  ///
  /// Returns a value between 0.0 and 1.0 representing the fraction
  /// of memory currently in use.
  static double memUsage() {
    _ensureInitialized();
    return _getMemoryUsage!();
  }

  /// Get the memory limit in bytes.
  ///
  /// In a container environment, returns the container's memory limit.
  /// On host, returns the total system memory.
  static int memoryLimitBytes() {
    _ensureInitialized();
    return _getMemoryLimitBytes!();
  }

  /// Get the memory currently used in bytes.
  ///
  /// In a container environment, returns the container's current memory usage.
  /// On host, returns the system's current memory usage.
  static int memoryUsedBytes() {
    _ensureInitialized();
    return _getMemoryUsedBytes!();
  }
}
