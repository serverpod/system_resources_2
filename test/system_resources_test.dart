import 'package:system_resources_2/system_resources_2.dart';
import 'package:test/test.dart';

void main() {
  test('Load dynamic library', () async {
    await SystemResources.init();
  });

  test('Get CPU load average', () {
    var cpuLoadAverage = SystemResources.cpuLoadAvg();
    expect(cpuLoadAverage, isPositive);
  });

  test('Get memory usage', () {
    var memUsage = SystemResources.memUsage();
    expect(memUsage, isPositive);
  });
}
