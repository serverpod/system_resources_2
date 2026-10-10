import 'dart:io';

import 'package:system_resources_2/system_resources_2.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    // Initialize library (no-op on Windows, kernel32 loads lazily)
    await SystemResources.init();
  });

  setUp(() {
    // Clear state before each test to ensure clean delta calculations
    SystemResources.clearState();
  });

  group('Windows metrics', () {
    test('memoryLimitBytes returns the total physical memory', () {
      final memLimit = SystemResources.memoryLimitBytes();

      // A real machine has at least 1 GB of physical memory
      expect(memLimit, greaterThan(1024 * 1024 * 1024));

      print('Memory Limit: ${(memLimit / 1024 / 1024).toStringAsFixed(2)} MB');
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('memoryUsedBytes is positive and within the limit', () {
      final memUsed = SystemResources.memoryUsedBytes();
      final memLimit = SystemResources.memoryLimitBytes();

      expect(memUsed, greaterThan(0));
      expect(memUsed, lessThanOrEqualTo(memLimit));

      print('Memory Used: ${(memUsed / 1024 / 1024).toStringAsFixed(2)} MB');
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('memUsage returns a value between 0 and 1', () {
      final memUsage = SystemResources.memUsage();

      expect(memUsage, greaterThan(0.0));
      expect(memUsage, lessThanOrEqualTo(1.0));

      print('Memory Usage: ${(memUsage * 100).toStringAsFixed(2)}%');
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('cpuLoadAvg first call returns 0.0', () {
      expect(SystemResources.cpuLoadAvg(), equals(0.0));
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('cpuLoadAvg reports CPU busy fraction between calls', () {
      // First call initializes the baseline
      SystemResources.cpuLoadAvg();

      // Generate CPU load for a short interval
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsedMilliseconds < 300) {}

      final load = SystemResources.cpuLoadAvg();

      // The spin loop keeps at least one core busy, so the load must be
      // greater than zero (at least 1 / numberOfProcessors).
      expect(load, greaterThan(0.0));
      expect(load, lessThanOrEqualTo(1.0));

      print('CPU Load: ${(load * 100).toStringAsFixed(2)}%');
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('cpuLimitCores equals the processor count', () {
      expect(
        SystemResources.cpuLimitCores(),
        equals(Platform.numberOfProcessors.toDouble()),
      );
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('cpuLimitMillicores returns processor count * 1000', () {
      expect(
        SystemResources.cpuLimitMillicores(),
        equals(Platform.numberOfProcessors * 1000),
      );
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);

    test('isContainerEnv returns false and cgroupVersion returns none', () {
      expect(SystemResources.isContainerEnv(), isFalse);
      expect(SystemResources.cgroupVersion(), equals(CgroupVersion.none));
    }, skip: !Platform.isWindows ? 'Only runs on Windows' : null);
  });
}
