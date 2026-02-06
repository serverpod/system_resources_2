/// A pure Dart library for monitoring system resources (CPU, memory).
///
/// This library is container-aware and works with cgroup v1/v2 environments,
/// including gVisor.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:system_resources_2/system_resources_2.dart';
///
/// void main() async {
///   // Check environment
///   print('Container: ${SystemResources.isContainerEnv()}');
///   print('Cgroup version: ${SystemResources.cgroupVersion()}');
///
///   // CPU monitoring (requires delta - call twice)
///   SystemResources.cpuUsageMillicores(); // First call initializes
///   await Future.delayed(Duration(seconds: 1));
///   print('CPU: ${SystemResources.cpuUsageMillicores()}m');
///
///   // Memory monitoring
///   print('Memory: ${SystemResources.memUsage() * 100}%');
/// }
/// ```
library;

export 'src/cgroup_detector.dart' show CgroupVersion, DetectedPlatform;
export 'src/system_resources.dart' show SystemResources;
