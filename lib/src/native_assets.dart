// Experimental native assets implementation
// This file demonstrates how the library could be migrated to use Dart's native assets feature.
// Native assets requires Dart SDK >=3.0.0, so this is forward-looking.
// The current implementation in base.dart and dylib.dart remains the default.

import 'dart:ffi' as ffi;

// Note: Native assets feature requires:
// 1. Dart SDK >=3.0.0
// 2. native_assets.yaml configuration file in package root
// 3. Build system support for native asset compilation
//
// When native assets is available, these external functions would be automatically
// linked to the native library without manual DynamicLibrary.open() calls.
//
// Example native_assets.yaml:
// ```
// assets:
//   - name: libsysres
//     path: lib/build/libsysres-{os}-{arch}.{ext}
//     os:
//       linux: libsysres-linux-{arch}.so
//       macos: libsysres-darwin-{arch}.dylib
//     arch:
//       x86_64: x86_64
//       arm64: aarch64 (linux) / arm64 (macos)
//       i686: i686
//       armv7l: armv7l
// ```

/// Native assets version of CPU load function.
/// When native assets is enabled, this would be automatically linked.
/// Currently, this is a placeholder that shows the intended API.
///
/// To use native assets:
/// 1. Upgrade SDK constraint to ">=3.0.0"
/// 2. Create native_assets.yaml configuration
/// 3. Replace @Native annotations with actual native asset bindings
/// 4. Remove manual DynamicLibrary loading from dylib.dart
///
/// Example (when native assets is available):
/// ```dart
/// @Native<Float Function()>(symbol: 'get_cpu_load', assetId: 'libsysres')
/// external double getCpuLoadNative();
/// ```
double getCpuLoadNative() {
  // Placeholder - would be implemented via @Native when native assets is available
  throw UnimplementedError(
    'Native assets not yet implemented. '
    'Use SystemResources.cpuLoadAvg() from base.dart instead.'
  );
}

/// Native assets version of memory usage function.
/// When native assets is enabled, this would be automatically linked.
///
/// Example (when native assets is available):
/// ```dart
/// @Native<Float Function()>(symbol: 'get_memory_usage', assetId: 'libsysres')
/// external double getMemoryUsageNative();
/// ```
double getMemoryUsageNative() {
  // Placeholder - would be implemented via @Native when native assets is available
  throw UnimplementedError(
    'Native assets not yet implemented. '
    'Use SystemResources.memUsage() from base.dart instead.'
  );
}
