# System Resources
Forked from [jonasroussel/system_resources](https://github.com/jonasroussel/system_resources). Brings the package up-to-date with latest Dart version.

[![pub package](https://img.shields.io/pub/v/system_resources.svg)](https://pub.dev/packages/system_resources)

Provides easy access to system resources (CPU load, memory usage).

## Requirements

- **Dart SDK**: 3.5.0 or higher

No C compiler is required - the package ships with pre-compiled binaries for all supported platforms.

## Usage

```dart
import 'package:system_resources/system_resources.dart';

void main() async {
  await SystemResources.init();

  print('CPU Load Average : ${(SystemResources.cpuLoadAvg() * 100).toInt()}%');
  print('Memory Usage     : ${(SystemResources.memUsage() * 100).toInt()}%');
}
```

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

## Features

### Linux

Function   | x86_64 | i686  | aarch64 | armv7l |
-----------|--------|-------|---------|--------|
cpuLoadAvg | 🟢     | 🟢    | 🟢      | 🟢     |
memUsage   | 🟢     | 🟢    | 🟢      | 🟢     |

### macOS

Function   | Intel | M1  |
-----------|-------|-----|
cpuLoadAvg | 🟢    | 🟢  |
memUsage   | 🟢    | 🟢  |

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
