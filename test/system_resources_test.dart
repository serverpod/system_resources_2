import 'dart:io';

import 'package:system_resources_2/system_resources_2.dart';
import 'package:test/test.dart';

void main() {
  group('SystemResources', () {
    test('cpuLoadAvg returns a non-negative value', () {
      final cpuLoad = SystemResources.cpuLoadAvg();

      // CPU load should be non-negative
      expect(cpuLoad, greaterThanOrEqualTo(0.0));

      // Print for debugging purposes
      print('CPU Load Average: ${(cpuLoad * 100).toStringAsFixed(2)}%');
    });

    test('memUsage returns a value between 0 and 1', () {
      final memUsage = SystemResources.memUsage();

      // Memory usage should be between 0 and 1
      expect(memUsage, greaterThanOrEqualTo(0.0));
      expect(memUsage, lessThanOrEqualTo(1.0));

      // Print for debugging purposes
      print('Memory Usage: ${(memUsage * 100).toStringAsFixed(2)}%');
    });

    test('native library loads correctly (no exceptions)', () {
      // Simply calling the functions should not throw if native library is loaded
      expect(() => SystemResources.cpuLoadAvg(), returnsNormally);
      expect(() => SystemResources.memUsage(), returnsNormally);
    });

    test('multiple calls return consistent results', () {
      // Call multiple times to ensure stability
      for (var i = 0; i < 5; i++) {
        final cpuLoad = SystemResources.cpuLoadAvg();
        final memUsage = SystemResources.memUsage();

        expect(cpuLoad, greaterThanOrEqualTo(0.0));
        expect(memUsage, greaterThanOrEqualTo(0.0));
        expect(memUsage, lessThanOrEqualTo(1.0));
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

    test('cpuLimitCores returns a positive value', () {
      final cpuLimit = SystemResources.cpuLimitCores();

      // CPU limit should be positive
      expect(cpuLimit, greaterThan(0.0));

      print('CPU Limit: $cpuLimit cores');
    });

    test('memoryLimitBytes returns a positive value', () {
      final memLimit = SystemResources.memoryLimitBytes();

      // Memory limit should be positive
      expect(memLimit, greaterThan(0));

      print('Memory Limit: ${(memLimit / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('memoryUsedBytes returns a positive value less than or equal to limit',
        () {
      final memUsed = SystemResources.memoryUsedBytes();
      final memLimit = SystemResources.memoryLimitBytes();

      // Memory used should be positive
      expect(memUsed, greaterThan(0));

      // Memory used should be less than or equal to limit
      expect(memUsed, lessThanOrEqualTo(memLimit));

      print('Memory Used: ${(memUsed / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('memUsage equals memoryUsedBytes / memoryLimitBytes', () {
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
}
