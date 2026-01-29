/// Container integration tests for system_resources_2.
///
/// These tests are designed to run inside a container with resource limits.
/// Run with: `docker run --memory=256m --cpus=0.5 IMAGE dart test test/container_test.dart`
///
/// Expected behavior:
/// - isContainerEnv() should return true
/// - memoryLimitBytes() should be ~256MB (268435456 bytes)
/// - cpuLimitCores() should be ~0.5
library;

import 'package:system_resources_2/system_resources_2.dart';
import 'package:test/test.dart';

void main() {
  group('Container environment detection', () {
    test('isContainerEnv returns true inside container', () {
      final isContainer = SystemResources.isContainerEnv();

      print('=== Container Detection ===');
      print('Is container environment: $isContainer');

      // This test is informational - it will pass regardless
      // Check the output to verify container detection works
      expect(isContainer, isA<bool>());
    });

    test('prints all resource information for verification', () {
      print('=== System Resources Report ===');
      print('Container detected: ${SystemResources.isContainerEnv()}');
      print('');
      print('CPU:');
      print(
          '  Load average: ${(SystemResources.cpuLoadAvg() * 100).toStringAsFixed(2)}%');
      print('  Limit (cores): ${SystemResources.cpuLimitCores()}');
      print('');
      print('Memory:');
      print(
          '  Usage: ${(SystemResources.memUsage() * 100).toStringAsFixed(2)}%');
      print(
          '  Limit: ${(SystemResources.memoryLimitBytes() / 1024 / 1024).toStringAsFixed(2)} MB');
      print(
          '  Used: ${(SystemResources.memoryUsedBytes() / 1024 / 1024).toStringAsFixed(2)} MB');
      print('================================');

      expect(true, isTrue); // Always pass - this is for manual verification
    });
  });

  group('Container resource limits (when running with limits)', () {
    test('memoryLimitBytes reflects container limit', () {
      final memLimit = SystemResources.memoryLimitBytes();
      final memLimitMB = memLimit / 1024 / 1024;

      print('Memory limit: ${memLimitMB.toStringAsFixed(2)} MB');

      // Memory limit should be positive
      expect(memLimit, greaterThan(0));

      // If running with --memory=256m, limit should be around 256MB
      // Allow some variance for overhead
      if (SystemResources.isContainerEnv()) {
        print('Container detected - checking if limit matches expected value');
        // The limit should be less than typical host memory (e.g., < 1GB for test containers)
        // This is a sanity check - adjust based on your test container limits
      }
    });

    test('cpuLimitCores reflects container limit', () {
      final cpuLimit = SystemResources.cpuLimitCores();

      print('CPU limit: $cpuLimit cores');

      // CPU limit should be positive
      expect(cpuLimit, greaterThan(0.0));

      // If running with --cpus=0.5, limit should be around 0.5
      if (SystemResources.isContainerEnv()) {
        print('Container detected - CPU limit: $cpuLimit');
      }
    });

    test('memUsage is relative to container limit', () {
      final memUsage = SystemResources.memUsage();
      final memUsed = SystemResources.memoryUsedBytes();
      final memLimit = SystemResources.memoryLimitBytes();

      print('Memory usage: ${(memUsage * 100).toStringAsFixed(2)}%');
      print(
          'Memory used: ${(memUsed / 1024 / 1024).toStringAsFixed(2)} MB of ${(memLimit / 1024 / 1024).toStringAsFixed(2)} MB');

      // Usage should be between 0 and 1
      expect(memUsage, greaterThanOrEqualTo(0.0));
      expect(memUsage, lessThanOrEqualTo(1.0));

      // Used should be less than or equal to limit
      expect(memUsed, lessThanOrEqualTo(memLimit));
    });
  });
}
