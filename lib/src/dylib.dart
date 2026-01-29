import 'dart:io';
import 'dart:ffi';
import 'dart:isolate' show Isolate;

/// Detect if running on 64-bit platform by checking pointer size
bool get _is64Bit => sizeOf<IntPtr>() == 8;

const Set<String> _supported = {
  'linux-x86_64',
  'linux-i686',
  'linux-aarch64',
  'linux-armv7l',
  'darwin-arm64',
  'darwin-x86_64',
};

/// Normalizes architecture names to support both Docker and standard naming conventions.
/// Maps: amd64 -> x86_64, arm64 -> aarch64 (for Linux) or arm64 (for macOS)
String _normalizeArchitecture(String arch, String os) {
  // Handle Docker naming conventions
  if (arch == 'amd64') {
    return 'x86_64';
  }
  if (arch == 'arm64' && os == 'linux') {
    return 'aarch64';
  }
  // Handle i386 -> i686 mapping
  if (arch == 'i386') {
    return 'i686';
  }
  return arch;
}

/// Detects the current platform architecture using Dart's Platform class.
/// Returns the architecture string in the format expected by the library.
String _detectArchitecture() {
  final os = Platform.operatingSystem.toLowerCase();
  
  if (os == 'linux') {
    // Check environment variables first (commonly set in Docker/build environments)
    final envArch = Platform.environment['TARGETARCH'] ?? 
                    Platform.environment['ARCH'] ?? 
                    Platform.environment['GOARCH'];
    
    if (envArch != null) {
      // Normalize environment-provided architecture
      return _normalizeArchitecture(envArch.toLowerCase(), os);
    }
    
    // Try to detect architecture by reading /proc/cpuinfo (doesn't require external binaries)
    try {
      final cpuinfo = File('/proc/cpuinfo');
      if (cpuinfo.existsSync()) {
        final content = cpuinfo.readAsStringSync();
        // Check for ARM architecture indicators
        if (content.contains('ARMv7')) {
          return 'armv7l';
        }
        if (content.contains('aarch64') || content.contains('ARMv8')) {
          return 'aarch64';
        }
        // Check for x86_64 indicators
        if (content.contains('x86_64') || content.contains('amd64')) {
          return 'x86_64';
        }
        // Check for i686/i386 indicators
        if (content.contains('i686') || content.contains('i386')) {
          return 'i686';
        }
      }
    } catch (e) {
      // /proc/cpuinfo not available or unreadable, fall through to default
    }
    
    // Fallback: use pointer size for basic detection
    if (_is64Bit) {
      // Default to x86_64 for 64-bit Linux if no other info available
      // Users can override with TARGETARCH environment variable
      return 'x86_64';
    } else {
      return 'i686';
    }
  } else if (os == 'macos' || os == 'darwin') {
    // macOS uses different architecture naming
    if (_is64Bit) {
      // Check environment variables that might indicate architecture
      // These are commonly set in Docker/build environments
      final envArch = Platform.environment['TARGETARCH'] ?? 
                      Platform.environment['ARCH'] ??
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
      
      // Note: Platform class doesn't directly expose CPU architecture on macOS
      // Without external binaries (uname/sysctl), we cannot reliably detect ARM vs x86_64
      // Default to x86_64 for backward compatibility
      // Users should set TARGETARCH environment variable for Apple Silicon (ARM64) systems
      // This is acceptable since Docker/build environments typically set TARGETARCH anyway
      return 'x86_64';
    }
    return 'x86_64';
  }
  
  throw Exception('Unsupported operating system: $os');
}

String _filename() {
  final os = Platform.operatingSystem.toLowerCase();
  var arch = _detectArchitecture();
  
  // Normalize architecture name
  arch = _normalizeArchitecture(arch, os);
  
  final ext = os == 'darwin' ? 'dylib' : 'so';
  final target = '$os-$arch';
  
  // Check if normalized target is supported
  if (!_supported.contains(target)) {
    // Try with original architecture name in case normalization changed it
    final originalArch = _detectArchitecture();
    final originalTarget = '$os-$originalArch';
    if (_supported.contains(originalTarget)) {
      return 'libsysres-$originalTarget.$ext';
    }
    throw Exception('Unsupported platform: $target! Supported platforms: ${_supported.join(", ")}');
  }

  return 'libsysres-$target.$ext';
}

/// Attempts to load the native library from multiple locations in order:
/// 1. Executable directory (same directory as the running executable)
/// 2. Package resolution path (for JIT mode)
/// 3. LD_LIBRARY_PATH environment variable (Linux only)
Future<DynamicLibrary> loadLibsysres = () async {
  final filename = _filename();
  final triedPaths = <String>[];
  
  // 1. Try executable directory first (works for both AOT and JIT)
  try {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final executablePath = '$executableDir/$filename';
    triedPaths.add(executablePath);
    
    if (File(executablePath).existsSync()) {
      return DynamicLibrary.open(executablePath);
    }
  } catch (e) {
    // Continue to next path if this fails
  }
  
  // 2. Try package resolution path (for JIT mode, or if executable dir doesn't work)
  try {
    final rootLibrary = 'package:system_resources_2/system_resources_2.dart';
    final build = (await Isolate.resolvePackageUri(Uri.parse(rootLibrary)))
        ?.resolve('build/');

    if (build != null) {
      final packagePath = build.resolve(filename).toFilePath();
      triedPaths.add(packagePath);
      
      if (File(packagePath).existsSync()) {
        return DynamicLibrary.open(packagePath);
      }
    }
  } catch (e) {
    // Continue to next path if this fails
  }
  
  // 3. Try LD_LIBRARY_PATH (Linux only)
  if (Platform.isLinux) {
    final ldLibraryPath = Platform.environment['LD_LIBRARY_PATH'];
    if (ldLibraryPath != null) {
      final paths = ldLibraryPath.split(':');
      for (final path in paths) {
        if (path.isEmpty) continue;
        final libraryPath = '$path/$filename';
        triedPaths.add(libraryPath);
        
        try {
          if (File(libraryPath).existsSync()) {
            return DynamicLibrary.open(libraryPath);
          }
        } catch (e) {
          // Continue to next path
        }
      }
    }
  }
  
  // 4. Legacy fallback: snapshot path (for AOT compiled executables)
  if (Platform.script.path.endsWith('.snapshot')) {
    final snapshotPath = '${File.fromUri(Platform.script).parent.path}/$filename';
    triedPaths.add(snapshotPath);
    
    try {
      if (File(snapshotPath).existsSync()) {
        return DynamicLibrary.open(snapshotPath);
      }
    } catch (e) {
      // Fall through to error
    }
  }
  
  // If all paths failed, throw an error with details
  throw Exception(
    'Library "$filename" could not be loaded!\n'
    'Tried paths:\n${triedPaths.map((p) => '  - $p').join('\n')}\n'
    'Please ensure the library file exists in one of these locations.'
  );
}();
