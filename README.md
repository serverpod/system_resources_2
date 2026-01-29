# System Resources
Forked from [jonasroussel/system_resources](https://github.com/jonasroussel/system_resources). Brings the package up-to-date with latest Dart version.

[![pub package](https://img.shields.io/pub/v/system_resources.svg)](https://pub.dev/packages/system_resources)

Provides easy access to system resources (CPU load, memory usage).

**Container-aware**: Automatically detects container environments and returns resource usage relative to container limits instead of host resources.

## Requirements

- **Dart SDK**: 3.5.0 or higher
- **Container detection**: Requires cgroups v2 (Kubernetes 1.25+ or Linux with cgroups v2 enabled)

No C compiler is required - the package ships with pre-compiled binaries for all supported platforms.

## Usage

```dart
import 'package:system_resources_2/system_resources_2.dart';

void main() async {
  await SystemResources.init();

  // Check if running in a container
  print('Container: ${SystemResources.isContainerEnv()}');

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

When running inside a container with cgroups v2, the library automatically:
- Returns CPU load normalized by container CPU limit
- Returns memory usage relative to container memory limit
- Provides absolute values for limits and usage

### gVisor Support

**CPU monitoring is not supported in gVisor.** gVisor does not virtualize the `getloadavg()` syscall, so `cpuLoadAvg()` always returns 0. For CPU monitoring in gVisor, use external solutions (e.g., Prometheus, Kubernetes metrics).

**Memory monitoring works correctly** in gVisor - it virtualizes `/proc/meminfo` to reflect container limits.

See [docs/GVISOR.md](docs/GVISOR.md) for details.

### Running

```bash
# Run directly
dart run example/example.dart

# Run tests
dart test

# Compile to executable
dart compile exe bin/my_app.dart -o my_app
# Copy the library next to the executable
cp lib/build/libsysres-linux-x86_64.so ./  # Linux x86_64
# cp lib/build/libsysres-darwin-arm64.dylib ./  # macOS ARM
```

### Docker Example

```dockerfile
FROM dart:stable

WORKDIR /app
COPY . .

RUN dart pub get
RUN dart compile exe bin/my_app.dart -o /app/my_app
# Copy library next to executable
RUN cp lib/build/libsysres-linux-x86_64.so /app/

CMD ["/app/my_app"]
```

### Testing with Container Limits

```bash
# Build the test image
docker build -t system_resources_test .

# Run with memory and CPU limits
docker run --memory=256m --cpus=0.5 system_resources_test

# Expected output:
# Container: true
# CPU Limit (cores): 0.5
# Memory Limit: 268435456 bytes (256 MB)
```

## API Reference

| Function | Description |
|----------|-------------|
| `isContainerEnv()` | Returns `true` if running in a container with cgroups v2 |
| `cpuLoadAvg()` | CPU load normalized by available cores (container or host) |
| `cpuLimitCores()` | CPU limit in cores (container limit or host cores) |
| `memUsage()` | Memory usage as fraction of limit (0.0 - 1.0) |
| `memoryLimitBytes()` | Memory limit in bytes (container limit or host total) |
| `memoryUsedBytes()` | Memory currently used in bytes |

## Features

### Linux

Function         | x86_64 | i686  | aarch64 | armv7l |
-----------------|--------|-------|---------|--------|
cpuLoadAvg       | 🟢     | 🟢    | 🟢      | 🟢     |
cpuLimitCores    | 🟢     | 🟢    | 🟢      | 🟢     |
memUsage         | 🟢     | 🟢    | 🟢      | 🟢     |
memoryLimitBytes | 🟢     | 🟢    | 🟢      | 🟢     |
memoryUsedBytes  | 🟢     | 🟢    | 🟢      | 🟢     |
isContainerEnv   | 🟢     | 🟢    | 🟢      | 🟢     |

### macOS

Function         | Intel | M1  |
-----------------|-------|-----|
cpuLoadAvg       | 🟢    | 🟢  |
cpuLimitCores    | 🟢    | 🟢  |
memUsage         | 🟢    | 🟢  |
memoryLimitBytes | 🟢    | 🟢  |
memoryUsedBytes  | 🟢    | 🟢  |
isContainerEnv   | 🟢    | 🟢  |

Note: On macOS, `isContainerEnv()` always returns `false` as containers are not natively supported.

### Windows

Function   | 64 bit | 32 bit | ARMv7 | ARMv8+ |
-----------|--------|--------|-------|--------|
cpuLoadAvg | 🔴     | 🔴     | 🔴    | 🔴     |
memUsage   | 🔴     | 🔴     | 🔴    | 🔴     |


🟢 : Coded, Compiled, Tested

🟠 : Coded, Not Compiled

🔴 : No Code

## Improve, compile & test

You are free to improve, compile and test `libsysres` C code for any platform not fully supported.

Github
[Issues](https://github.com/jonasroussel/system_resources/issues) | [Pull requests](https://github.com/jonasroussel/system_resources/pulls)
