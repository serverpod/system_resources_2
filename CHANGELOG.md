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
