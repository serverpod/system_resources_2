# System Resources
Forked from [jonasroussel/system_resources](https://github.com/jonasroussel/system_resources). Brings the package up-to-date with latest Dart version.

[![pub package](https://img.shields.io/pub/v/system_resources_2.svg)](https://pub.dev/packages/system_resources_2)

Provides easy access to system resources (CPU load, memory usage).

**Container-aware**: Automatically detects container environments and returns resource usage relative to container limits instead of host resources.

## Key Features

- **Hybrid implementation**: Pure Dart on Linux, FFI on macOS
- **gVisor compatible**: Works in gVisor environments (uses cgroup accounting, not getloadavg)
- **Cgroup v1/v2 support**: Automatically detects and uses appropriate paths
- **No native dependencies on Linux**: Pure Dart file I/O, no glibc requirements
- **Serverpod compatible**: Drop-in replacement for system_resources package

## Requirements

- **Dart SDK**: 3.5.0 or higher
- **Linux**: No native dependencies (pure Dart implementation)
- **macOS**: 10.15 (Catalina) or higher (uses pre-built dylibs)
- **Container detection**: Supports cgroups v1 and v2

## Usage

```dart
import 'package:system_resources_2/system_resources_2.dart';

void main() async {
  // Initialize (required for macOS, no-op on Linux)
  await SystemResources.init();

  // Check if running in a container
  print('Container: ${SystemResources.isContainerEnv()}');
  print('Cgroup version: ${SystemResources.cgroupVersion()}');

  // CPU information (auto-detects container limits)
  print('CPU Load Average : ${(SystemResources.cpuLoadAvg() * 100).toInt()}%');
  print('CPU Limit (cores): ${SystemResources.cpuLimitCores()}');

  // Memory information (auto-detects container limits)
  print('Memory Usage     : ${(SystemResources.memUsage() * 100).toInt()}%');
  print('Memory Limit     : ${SystemResources.memoryLimitBytes()} bytes');
  print('Memory Used      : ${SystemResources.memoryUsedBytes()} bytes');
}
```

## Container Support

The library automatically detects container environments using cgroups:
- Returns CPU load from cgroup accounting (not getloadavg)
- Returns memory usage relative to container memory limit
- Provides absolute values for limits and usage

### gVisor Support

Unlike the original implementation, **CPU monitoring works in gVisor**! This version uses cgroup CPU accounting (`/sys/fs/cgroup/cpu.stat`) instead of `getloadavg()`, which gVisor does virtualize.

**Memory monitoring** also works correctly via gVisor's virtualized `/proc/meminfo`.

See [doc/GVISOR.md](doc/GVISOR.md) for details.

### Running

```bash
# Run directly (no compilation needed on Linux!)
dart run example/example.dart

# Run tests
dart test

# Compile to executable
dart compile exe bin/my_app.dart -o my_app
# On macOS, copy the library next to the executable:
# cp lib/build/libsysres-darwin-arm64.dylib ./
# On Linux, no native library needed!
```

### Docker Example

```dockerfile
FROM dart:stable

WORKDIR /app
COPY . .

RUN dart pub get
RUN dart compile exe bin/my_app.dart -o /app/my_app

# No native library copy needed - Linux uses pure Dart!
CMD ["/app/my_app"]
```

### Testing with Container Limits

```bash
# Build the test image
docker build -f ci/Dockerfile.test -t system_resources_test .

# Run with memory and CPU limits
docker run --memory=256m --cpus=0.5 system_resources_test

# Expected output:
# Container: true
# Cgroup version: CgroupVersion.v2
# CPU Limit (cores): 0.5
# Memory Limit: 268435456 bytes (256 MB)
```

## API Reference

| Function | Description |
|----------|-------------|
| `init()` | Initialize library (required for macOS, no-op on Linux) |
| `isContainerEnv()` | Returns `true` if running in a container with cgroup limits |
| `cgroupVersion()` | Returns detected cgroup version (v1, v2, or none) |
| `cpuLoadAvg()` | CPU load normalized by available cores (container or host) |
| `cpuLimitCores()` | CPU limit in cores (container limit or host cores) |
| `cpuUsageMillicores()` | CPU usage in millicores (1000m = 1 core) |
| `memUsage()` | Memory usage as fraction of limit (0.0 - 1.0) |
| `memoryLimitBytes()` | Memory limit in bytes (container limit or host total) |
| `memoryUsedBytes()` | Memory currently used in bytes |

## Platform Support

### Linux (Pure Dart - No Native Dependencies)

| Function         | x86_64 | aarch64 | armv7l | i686 |
|------------------|--------|---------|--------|------|
| cpuLoadAvg       | ✅     | ✅      | ✅     | ✅   |
| cpuLimitCores    | ✅     | ✅      | ✅     | ✅   |
| memUsage         | ✅     | ✅      | ✅     | ✅   |
| memoryLimitBytes | ✅     | ✅      | ✅     | ✅   |
| memoryUsedBytes  | ✅     | ✅      | ✅     | ✅   |
| isContainerEnv   | ✅     | ✅      | ✅     | ✅   |

### macOS (FFI with Pre-built Dylibs)

| Function         | Intel | Apple Silicon |
|------------------|-------|---------------|
| cpuLoadAvg       | ✅    | ✅            |
| cpuLimitCores    | ✅    | ✅            |
| memUsage         | ✅    | ✅            |
| memoryLimitBytes | ✅    | ✅            |
| memoryUsedBytes  | ✅    | ✅            |
| isContainerEnv   | ✅    | ✅            |

Note: On macOS, `isContainerEnv()` always returns `false` as containers are not natively supported.

### Windows

Not currently supported.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SystemResources API                       │
├─────────────────────────────────────────────────────────────┤
│  Linux (Pure Dart)           │  macOS (FFI)                 │
│  ├─ cgroup_cpu.dart          │  └─ macos_ffi.dart           │
│  ├─ cgroup_memory.dart       │      └─ libsysres-darwin-*.  │
│  └─ cgroup_detector.dart     │          dylib               │
│      │                       │                               │
│      ▼                       │                               │
│  /sys/fs/cgroup/* (v1/v2)    │                               │
│  /proc/loadavg (host)        │                               │
│  /proc/meminfo (fallback)    │                               │
└─────────────────────────────────────────────────────────────┘
```

## Contributing

You are free to improve and contribute to this package.

GitHub: [Issues](https://github.com/serverpod/system_resources_2/issues) | [Pull requests](https://github.com/serverpod/system_resources_2/pulls)
