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
}
