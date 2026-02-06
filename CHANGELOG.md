## 2.2.1

- Log warning to stderr when running on Windows or other unsupported platforms

## 2.2.0

### Pure Dart on Linux

- **Hybrid architecture**: Linux now uses pure Dart (reading `/proc` and cgroup filesystems directly), eliminating the need for native `.so` binaries. macOS continues to use FFI with native `.dylib` binaries.
- **Removed Linux native binaries**: `libsysres-linux-*.so` files are no longer shipped, reducing package size and improving compatibility across Linux architectures.

### Cgroup v1 Support

- **Cgroup v1 (legacy hierarchy)**: CPU and memory monitoring now works on systems using cgroup v1 in addition to cgroup v2.

### New APIs

- `cgroupVersion()` - Returns detected cgroup version (v1, v2, or none)
- `cpuLoad()` - CPU load as a fraction of the cgroup limit (delta-based)
- `cpuUsageMillicores()` - CPU usage in millicores (delta-based)
- `cpuUsageMicros()` - Raw cumulative CPU usage in microseconds
- `cpuLimitMillicores()` - CPU limit in millicores
- `clearState()` - Clears all cached platform/CPU state (useful for testing)
- New exported enums: `CgroupVersion`, `DetectedPlatform`

### Bug Fixes

- Resolve process's actual cgroup path for memory metrics on native Linux hosts
- Unify CPU load normalization to respect `SYSRES_CPU_CORES` environment variable
- Use `DynamicLibrary.open` directly instead of `File.existsSync` for better compatibility
- Improve native library compatibility with older glibc versions

## 2.1.1

- Fix package directory structure to follow Dart conventions (rename `docs/` to `doc/`)

## 2.1.0

### Container-Aware Features

- **Container detection**: Automatically detects container environments using cgroups v2
- **New functions**:
  - `isContainerEnv()` - Returns true if running in a container with cgroups v2
  - `cpuLimitCores()` - Returns CPU limit in cores (container limit or host cores)
  - `memoryLimitBytes()` - Returns memory limit in bytes
  - `memoryUsedBytes()` - Returns memory currently used in bytes
- **Auto-detection**: `cpuLoadAvg()` and `memUsage()` now automatically use container limits when available

### Requirements

- Kubernetes 1.25+ (cgroups v2 is default)
- Non-k8s environments must have cgroups v2 enabled

### Known Limitations

- **gVisor**: CPU monitoring not supported (always returns 0). Memory monitoring works correctly.

## 1.6.0

- https://github.com/jonasroussel/system_resources/pull/2

## 1.5.0

- Adding `darwin-arm64` (Mac M1) to support list

## 1.4.2

- Support for `linux-armv7l`
- Better README.md

## 1.4.1

- Fixing linux negative memory

## 1.4.0

- Improve linux memory usage (substract buffers & cached)

## 1.3.0

- Improve linux memory usage
- Adding `linux-aarch64` to support list

## 1.2.0

- Improve linux cpu load average
- Better cpu arch detection

## 1.1.0

- Improve macos cpu load average

## 1.0.0

- First version with every based features
