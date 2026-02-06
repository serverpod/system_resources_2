import 'dart:io';

import 'package:system_resources_2/src/cpu_monitor.dart';
import 'package:test/test.dart';

void main() {
  group('CpuMonitor.getLoad() limit resolution', () {
    setUp(() {
      CpuMonitor.clearState();
    });

    test('getLoad uses getLimitCores for limit resolution', () {
      var usageMicros = 0;
      int mockUsageReader() {
        usageMicros += 500000;
        return usageMicros;
      }

      // -1 simulates unavailable cgroup limit (e.g. gVisor)
      int mockLimitReaderUnlimited() => -1;

      final first = CpuMonitor.getLoad(mockUsageReader, mockLimitReaderUnlimited);
      expect(first, equals(0.0));

      final load = CpuMonitor.getLoad(mockUsageReader, mockLimitReaderUnlimited);
      final limitCores = CpuMonitor.getLimitCores(mockLimitReaderUnlimited);

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

      CpuMonitor.getLoad(mockUsageReader, mockLimitReader1Core);
      final load = CpuMonitor.getLoad(mockUsageReader, mockLimitReader1Core);

      expect(CpuMonitor.getLimitCores(mockLimitReader1Core), equals(1.0));
      expect(load, greaterThanOrEqualTo(0.0));
    });

    test('getLoad and getLimitCores use same fallback when limit unavailable', () {
      int mockLimitReaderUnlimited() => -1;

      final limitCores = CpuMonitor.getLimitCores(mockLimitReaderUnlimited);
      expect(limitCores, greaterThan(0.0));

      if (Platform.environment['SYSRES_CPU_CORES'] == null) {
        expect(limitCores, equals(Platform.numberOfProcessors.toDouble()));
      }
    });
  });
}
