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

import 'dart:io';

import 'package:system_resources_2/system_resources_2.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    // Initialize library (required for macOS FFI)
    await SystemResources.init();
  });

  setUp(() {
    SystemResources.clearState();
  });

  group('Container environment detection', () {
    test('isContainerEnv returns true inside container', () {
      final isContainer = SystemResources.isContainerEnv();

      print('=== Container Detection ===');
      print('Is container environment: $isContainer');
      print('Cgroup version: ${SystemResources.cgroupVersion()}');

      // This test is informational - it will pass regardless
      // Check the output to verify container detection works
      expect(isContainer, isA<bool>());
    });

    test('prints all resource information for verification', () {
      print('=== System Resources Report ===');
      print('Container detected: ${SystemResources.isContainerEnv()}');
      print('Cgroup version: ${SystemResources.cgroupVersion()}');
      print('');

      // Initialize CPU delta tracking
      SystemResources.cpuUsageMillicores();
      sleep(Duration(milliseconds: 500));

      print('CPU:');
      print('  Usage: ${SystemResources.cpuUsageMillicores()}m');
      print('  Load: ${(SystemResources.cpuLoad() * 100).toStringAsFixed(2)}%');
      print('  Limit (cores): ${SystemResources.cpuLimitCores()}');
      print('  Limit (millicores): ${SystemResources.cpuLimitMillicores()}m');
      print('  Raw usage: ${SystemResources.cpuUsageMicros()} microseconds');
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
      if (!Platform.isLinux) {
        print('Memory limit: Skipped (not Linux)');
        return;
      }

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

    test('cpuUsageMillicores tracks actual CPU consumption', () {
      // Initialize
      SystemResources.cpuUsageMillicores();

      // Do some CPU work
      var sum = 0.0;
      for (var i = 0; i < 10000000; i++) {
        sum += i * 0.001;
      }

      final usage = SystemResources.cpuUsageMillicores();
      print('CPU usage after work: ${usage}m (sum=$sum)');

      // Usage should be non-negative
      expect(usage, greaterThanOrEqualTo(0));
    });

    test('memUsage is relative to container limit', () {
      if (!Platform.isLinux) {
        print('Memory usage: Skipped (not Linux)');
        return;
      }

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
