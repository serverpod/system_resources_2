import 'dart:io';
import 'dart:ffi';
import 'dart:isolate' show Isolate;

const Set<String> _supported = {
  'linux-x86_64',
  'linux-i686',
  'linux-aarch64',
  'linux-armv7l',
  'darwin-arm64',
  'darwin-x86_64',
};

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
      return envArch.toLowerCase();
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
    
    // Fallback: use Platform.is64Bit for basic detection
    if (Platform.is64Bit) {
      // Default to x86_64 for 64-bit Linux if no other info available
      // Users can override with TARGETARCH environment variable
      return 'x86_64';
    } else {
      return 'i686';
    }
  } else if (os == 'macos' || os == 'darwin') {
    // macOS uses different architecture naming
    if (Platform.is64Bit) {
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
  final ext = os == 'darwin' ? 'dylib' : 'so';

  if (arch == 'i386') arch = 'i686';

  final target = os + '-' + arch;
  if (!_supported.contains(target)) {
    throw Exception('Unsupported platform: $target!');
  }

  return 'libsysres-$target.$ext';
}

Future<DynamicLibrary> loadLibsysres = () async {
  String objectFile;

  if (Platform.script.path.endsWith('.snapshot')) {
    objectFile = File.fromUri(Platform.script).parent.path + '/' + _filename();
  } else {
    final rootLibrary = 'package:system_resources_2/system_resources_2.dart';
    final build = (await Isolate.resolvePackageUri(Uri.parse(rootLibrary)))
        ?.resolve('build/');

    if (build == null) {
      throw Exception('Library could not be loaded!');
    }

    objectFile = build.resolve(_filename()).toFilePath();
  }

  return DynamicLibrary.open(objectFile);
}();
