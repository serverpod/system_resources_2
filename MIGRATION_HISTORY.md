# Migration History: Native Assets to Pre-compiled Binaries

This document explains the journey of trying to use Dart's native assets feature and why we ultimately reverted to shipping pre-compiled binaries.

## Background

The `system_resources` package provides CPU load and memory usage information by calling native C code via FFI. The original package on pub.dev ships with pre-compiled `.so` (Linux) and `.dylib` (macOS) binaries.

## Initial Goal

Modernize the library to use Dart's **native assets** feature, which:
- Automatically compiles C code at build time
- Eliminates the need to ship pre-compiled binaries
- Handles cross-platform compilation seamlessly

## What We Tried

### Attempt 1: Native Assets with `@ffi.Native` Annotations

We converted the library to use native assets:

```dart
@ffi.Native<ffi.Float Function()>(
  symbol: 'get_cpu_load',
  assetId: 'package:system_resources/libsysres',
)
external double _getCpuLoad();
```

With a build hook in `hook/build.dart`:

```dart
final builder = CBuilder.library(
  name: 'sysres',
  assetName: 'libsysres',
  sources: [
    'lib/src/libsysres/cpu.c',
    'lib/src/libsysres/memory.c',
  ],
);
await builder.run(input: input, output: output);
```

**Result**: This worked locally with `--enable-experiment=native-assets` flag.

### Attempt 2: Running in Docker

We tried running in Docker with various Dart images:

| Image | Result |
|-------|--------|
| `dart:3.8` | `Unavailable experiment: native-assets` |
| `dart:3.10` | Required C compiler installation |
| `dart:beta` | Experiment still not available on stable |
| `dart:dev` | Image doesn't exist |

**Problem**: Native assets requires:
1. The experimental flag (only available on dev channel, not stable)
2. A C compiler (`clang`) at build time
3. Build tools (`build-essential`) in Docker

### Attempt 3: Stable Dart with Native Assets

Even with Dart 3.10 (latest stable), native assets is still considered experimental and requires the `--enable-experiment=native-assets` flag, which is not available on the stable channel.

**Error**:
```
Unavailable experiment: native-assets (this experiment is only available on 
the main, dev channels, this current channel is stable)
```

### Other Issues Encountered

1. **`Platform.is64Bit` doesn't exist**: The original fork used a non-existent API. Fixed using `sizeOf<IntPtr>() == 8`.

2. **Architecture mismatch**: Docker's `uname -m` returns `amd64` but libraries are named `x86_64`. Required normalization.

3. **Missing binaries in git**: When using a git dependency, `dart pub get` clones the repo but pre-compiled binaries are typically in `.gitignore`.

## Why We Reverted

1. **Experimental status**: Native assets is not available on Dart stable channel
2. **Build complexity**: Requires C compiler in production Docker images
3. **User friction**: Users need experimental flags and build tools
4. **Deployment issues**: CI/CD pipelines need additional configuration

## Final Solution

We reverted to the traditional `DynamicLibrary.open()` approach with pre-compiled binaries:

### Changes Made

1. **Added pre-compiled binaries** to `lib/build/`:
   - `libsysres-linux-x86_64.so`
   - `libsysres-linux-aarch64.so`
   - `libsysres-linux-armv7l.so`
   - `libsysres-linux-i686.so`
   - `libsysres-darwin-arm64.dylib`
   - `libsysres-darwin-x86_64.dylib`

2. **Updated `.gitignore`** to allow `.so` and `.dylib` files

3. **Rewrote `lib/src/base.dart`** to use `DynamicLibrary.open()` with smart path resolution:
   - Checks executable directory
   - Checks `lib/build/` relative paths
   - Checks pub cache for package dependencies
   - Falls back to system library path

4. **Simplified Dockerfile** - No C compiler needed

5. **Removed native assets files**:
   - `hook/build.dart`
   - `native_assets.yaml.example`
   - Native assets dev dependencies

6. **Updated documentation** to reflect simpler usage

## Benefits of This Approach

- Works on stable Dart (no experimental flags)
- No C compiler required at build time
- Simpler Docker images
- Faster builds (no compilation step)
- Works immediately after `dart pub get`

## Future Considerations

When native assets graduates from experimental to stable in a future Dart release, the library could be updated to support both approaches:
- Native assets for users who want automatic compilation
- Pre-compiled binaries as fallback for simpler deployment

## Files Changed

| File | Change |
|------|--------|
| `.gitignore` | Commented out `*.so`, `*.dylib` exclusions |
| `lib/src/base.dart` | Rewrote to use `DynamicLibrary.open()` |
| `lib/build/*` | Added pre-compiled binaries |
| `Dockerfile` | Simplified (removed C compiler) |
| `README.md` | Updated usage instructions |
| `pubspec.yaml` | Removed native assets dependencies |
| `hook/build.dart` | Deleted |
| `native_assets.yaml.example` | Deleted |

## References

- [Dart Native Assets Documentation](https://dart.dev/interop/c-interop#native-assets)
- [native_toolchain_c package](https://pub.dev/packages/native_toolchain_c)
- [Original system_resources on pub.dev](https://pub.dev/packages/system_resources)
