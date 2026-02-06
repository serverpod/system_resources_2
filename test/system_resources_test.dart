import 'dart:io';

import 'package:system_resources_2/src/cgroup_cpu.dart';
import 'package:system_resources_2/system_resources_2.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    // Initialize library (required for macOS FFI)
    await SystemResources.init();
  });

  setUp(() {
    // Clear state before each test to ensure clean delta calculations
    SystemResources.clearState();
  });

  group('SystemResources', () {
    test('cpuLoad returns a non-negative value', () {
      // First call initializes delta tracking, returns 0
      final firstCall = SystemResources.cpuLoad();
      expect(firstCall, equals(0.0));

      // On Linux, subsequent calls would return actual load
      // On non-Linux, always returns 0
      if (Platform.isLinux) {
        // Wait a bit for some CPU activity
        sleep(Duration(milliseconds: 100));
        final cpuLoad = SystemResources.cpuLoad();
        expect(cpuLoad, greaterThanOrEqualTo(0.0));
        print('CPU Load: ${(cpuLoad * 100).toStringAsFixed(2)}%');
      } else {
        print('CPU Load: Not supported on ${Platform.operatingSystem}');
      }
    });

    test('memUsage returns a value between 0 and 1', () {
      // Works on both Linux (pure Dart) and macOS (FFI)
      if (!Platform.isLinux && !Platform.isMacOS) {
        expect(SystemResources.memUsage(), equals(0.0));
        print('Memory Usage: Not supported on ${Platform.operatingSystem}');
        return;
      }

      final memUsage = SystemResources.memUsage();

      // Memory usage should be between 0 and 1
      expect(memUsage, greaterThanOrEqualTo(0.0));
      expect(memUsage, lessThanOrEqualTo(1.0));

      print('Memory Usage: ${(memUsage * 100).toStringAsFixed(2)}%');
    });

    test('pure Dart implementation works (no native library needed)', () {
      // These should not throw - pure Dart, no FFI
      expect(() => SystemResources.cpuLoad(), returnsNormally);
      expect(() => SystemResources.memUsage(), returnsNormally);
      expect(() => SystemResources.isContainerEnv(), returnsNormally);
      expect(() => SystemResources.cgroupVersion(), returnsNormally);
    });

    test('multiple calls return consistent results', () {
      // Initialize delta tracking
      SystemResources.cpuLoad();

      if (Platform.isLinux) {
        sleep(Duration(milliseconds: 50));
      }

      // Call multiple times to ensure stability
      for (var i = 0; i < 5; i++) {
        final cpuLoad = SystemResources.cpuLoad();
        final memUsage = SystemResources.memUsage();

        expect(cpuLoad, greaterThanOrEqualTo(0.0));
        expect(memUsage, greaterThanOrEqualTo(0.0));

        if (Platform.isLinux || Platform.isMacOS) {
          expect(memUsage, lessThanOrEqualTo(1.0));
        }
      }
    });
  });

  group('Container-aware functions', () {
    test('isContainerEnv returns a boolean without exceptions', () {
      expect(() => SystemResources.isContainerEnv(), returnsNormally);
      final isContainer = SystemResources.isContainerEnv();
      expect(isContainer, isA<bool>());

      print('Container environment: $isContainer');
    });

    test('cgroupVersion returns detected version', () {
      final version = SystemResources.cgroupVersion();
      expect(version, isA<CgroupVersion>());

      print('Cgroup version: $version');
    });

    test('cpuLimitCores returns a positive value', () {
      final cpuLimit = SystemResources.cpuLimitCores();

      // CPU limit should be positive
      expect(cpuLimit, greaterThan(0.0));

      print('CPU Limit: $cpuLimit cores');
    });

    test('cpuLimitMillicores returns expected value', () {
      final cpuLimitMillicores = SystemResources.cpuLimitMillicores();

      if (Platform.isLinux) {
        // Either -1 (unlimited) or positive
        expect(
            cpuLimitMillicores == -1 || cpuLimitMillicores > 0, isTrue);
      } else {
        // On non-Linux, returns host CPU count * 1000
        expect(cpuLimitMillicores, equals(Platform.numberOfProcessors * 1000));
      }

      print('CPU Limit: ${cpuLimitMillicores}m');
    });

    test('cpuUsageMillicores returns expected value', () {
      // First call initializes
      final first = SystemResources.cpuUsageMillicores();
      expect(first, equals(0));

      if (Platform.isLinux) {
        sleep(Duration(milliseconds: 100));
        final usage = SystemResources.cpuUsageMillicores();
        expect(usage, greaterThanOrEqualTo(0));
        print('CPU Usage: ${usage}m');
      }
    });

    test('cpuUsageMicros returns cumulative value', () {
      final micros = SystemResources.cpuUsageMicros();

      if (Platform.isLinux && SystemResources.cgroupVersion() != CgroupVersion.none) {
        // Should be a large cumulative value
        expect(micros, greaterThanOrEqualTo(0));
        print('CPU Usage (raw): $micros microseconds');
      } else {
        expect(micros, equals(0));
      }
    });

    test('memoryLimitBytes returns a positive value', () {
      // Works on Linux (pure Dart) and macOS (FFI)
      if (!Platform.isLinux && !Platform.isMacOS) {
        expect(SystemResources.memoryLimitBytes(), equals(0));
        return;
      }

      final memLimit = SystemResources.memoryLimitBytes();

      // Memory limit should be positive
      expect(memLimit, greaterThan(0));

      print('Memory Limit: ${(memLimit / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('memoryUsedBytes returns a positive value less than or equal to limit',
        () {
      // Works on Linux (pure Dart) and macOS (FFI)
      if (!Platform.isLinux && !Platform.isMacOS) {
        expect(SystemResources.memoryUsedBytes(), equals(0));
        return;
      }

      final memUsed = SystemResources.memoryUsedBytes();
      final memLimit = SystemResources.memoryLimitBytes();

      // Memory used should be positive
      expect(memUsed, greaterThan(0));

      // Memory used should be less than or equal to limit
      expect(memUsed, lessThanOrEqualTo(memLimit));

      print('Memory Used: ${(memUsed / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('memUsage equals memoryUsedBytes / memoryLimitBytes', () {
      if (!Platform.isLinux && !Platform.isMacOS) {
        return;
      }

      final memUsage = SystemResources.memUsage();
      final memUsed = SystemResources.memoryUsedBytes();
      final memLimit = SystemResources.memoryLimitBytes();

      // Calculate expected usage
      final expectedUsage = memUsed / memLimit;

      // Allow for small floating point differences
      expect(memUsage, closeTo(expectedUsage, 0.01));
    });

    test('on macOS, isContainerEnv should return false', () {
      if (Platform.isMacOS) {
        expect(SystemResources.isContainerEnv(), isFalse);
      }
    }, skip: !Platform.isMacOS ? 'Only runs on macOS' : null);
  });

  group('CgroupCpu.getLoad() limit resolution', () {
    setUp(() {
      CgroupCpu.clearState();
    });

    test('getLoad uses getLimitCores for limit resolution', () {
      var usageMicros = 0;
      int mockUsageReader() {
        usageMicros += 500000;
        return usageMicros;
      }

      // -1 simulates unavailable cgroup limit (e.g. gVisor)
      int mockLimitReaderUnlimited() => -1;

      final first = CgroupCpu.getLoad(mockUsageReader, mockLimitReaderUnlimited);
      expect(first, equals(0.0));

      final load = CgroupCpu.getLoad(mockUsageReader, mockLimitReaderUnlimited);
      final limitCores = CgroupCpu.getLimitCores(mockLimitReaderUnlimited);

      expect(load, greaterThanOrEqualTo(0.0));
      expect(limitCores, greaterThan(0.0));
    });

    test('getLoad normalizes against cgroup limit when available', () {
      var usageMicros = 0;
      int mockUsageReader() {
        usageMicros += 500000;
        return usageMicros;
      }

      int mockLimitReader1Core() => 1000;

      CgroupCpu.getLoad(mockUsageReader, mockLimitReader1Core);
      final load = CgroupCpu.getLoad(mockUsageReader, mockLimitReader1Core);

      expect(CgroupCpu.getLimitCores(mockLimitReader1Core), equals(1.0));
      expect(load, greaterThanOrEqualTo(0.0));
    });

    test('getLoad and getLimitCores use same fallback when limit unavailable', () {
      int mockLimitReaderUnlimited() => -1;

      final limitCores = CgroupCpu.getLimitCores(mockLimitReaderUnlimited);
      expect(limitCores, greaterThan(0.0));

      if (Platform.environment['SYSRES_CPU_CORES'] == null) {
        expect(limitCores, equals(Platform.numberOfProcessors.toDouble()));
      }
    });
  });
}
