import 'dart:io';

import 'package:system_resources_2/system_resources_2.dart';

void main() async {
  // Container detection
  final isContainer = SystemResources.isContainerEnv();
  final cgroupVersion = SystemResources.cgroupVersion();
  print('Environment      : ${isContainer ? "Container" : "Host"}');
  print('Cgroup version   : $cgroupVersion');
  print('');

  // CPU information - requires delta calculation
  print('CPU:');
  print('  Limit (cores)  : ${SystemResources.cpuLimitCores().toStringAsFixed(2)}');
  print('  Limit          : ${SystemResources.cpuLimitMillicores()}m');

  // Initialize CPU tracking and wait for measurement
  SystemResources.cpuUsageMillicores();
  await Future.delayed(Duration(seconds: 1));

  print('  Usage          : ${SystemResources.cpuUsageMillicores()}m');
  print('  Load           : ${(SystemResources.cpuLoad() * 100).toStringAsFixed(1)}%');
  print('');

  // Memory information
  final memLimitMB = SystemResources.memoryLimitBytes() / 1024 / 1024;
  final memUsedMB = SystemResources.memoryUsedBytes() / 1024 / 1024;
  print('Memory:');
  print('  Usage          : ${(SystemResources.memUsage() * 100).toInt()}%');
  print('  Limit          : ${memLimitMB.toStringAsFixed(2)} MB');
  print('  Used           : ${memUsedMB.toStringAsFixed(2)} MB');

  // Platform check
  if (!Platform.isLinux) {
    print('');
    print('Note: Full functionality requires Linux with cgroups.');
  }
}
