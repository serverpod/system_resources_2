import 'package:system_resources_2/system_resources_2.dart';

void main() {
  // Container detection
  final isContainer = SystemResources.isContainerEnv();
  print('Environment      : ${isContainer ? "Container (cgroups v2)" : "Host"}');
  print('');

  // CPU information
  print('CPU:');
  print('  Load Average   : ${(SystemResources.cpuLoadAvg() * 100).toInt()}%');
  print('  Limit (cores)  : ${SystemResources.cpuLimitCores().toStringAsFixed(2)}');
  print('');

  // Memory information
  final memLimitMB = SystemResources.memoryLimitBytes() / 1024 / 1024;
  final memUsedMB = SystemResources.memoryUsedBytes() / 1024 / 1024;
  print('Memory:');
  print('  Usage          : ${(SystemResources.memUsage() * 100).toInt()}%');
  print('  Limit          : ${memLimitMB.toStringAsFixed(2)} MB');
  print('  Used           : ${memUsedMB.toStringAsFixed(2)} MB');
}
