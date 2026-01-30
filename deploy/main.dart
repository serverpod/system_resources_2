import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:async';
import 'dart:math';

typedef GetVersionNative = ffi.Int32 Function();
typedef GetVersionDart = int Function();

typedef GetUsageNative = ffi.Int64 Function();
typedef GetUsageDart = int Function();

typedef GetLimitNative = ffi.Int32 Function();
typedef GetLimitDart = int Function();

late final GetVersionDart _getCgroupVersion;
late final GetUsageDart _getCpuUsageMicros;
late final GetLimitDart _getCpuLimitMillicores;

void _initFFI() {
  final dylib = ffi.DynamicLibrary.open('/app/libmonitor.so');
  _getCgroupVersion = dylib.lookupFunction<GetVersionNative, GetVersionDart>(
    'get_cgroup_version',
  );
  _getCpuUsageMicros = dylib.lookupFunction<GetUsageNative, GetUsageDart>(
    'get_cpu_usage_micros',
  );
  _getCpuLimitMillicores = dylib.lookupFunction<GetLimitNative, GetLimitDart>(
    'get_cpu_limit_millicores',
  );
}

void main(List<String> args) async {
  final burnMode = args.contains('--burn');

  _initFFI();

  print('--- Dart CPU Monitor (FFI) ---');
  if (burnMode) print('--- BURN MODE ENABLED ---');

  final version = _getCgroupVersion();
  print('Cgroup version: ${version == 0 ? "unknown" : "v$version"}');

  int? cpuLimitMillicores = _getCpuLimitMillicores();
  if (cpuLimitMillicores == -1) {
    final envLimit = Platform.environment['CPU_LIMIT_MILLICORES'];
    if (envLimit != null) {
      cpuLimitMillicores = int.tryParse(envLimit);
    }
  }
  print(
    'CPU limit: ${cpuLimitMillicores == null || cpuLimitMillicores == -1 ? "unlimited" : "${cpuLimitMillicores}m"}',
  );

  int? previousMicros;
  DateTime? previousTime;

  Timer.periodic(Duration(seconds: 2), (timer) {
    final now = DateTime.now();
    final cpuMicros = _getCpuUsageMicros();

    String output = '[${now.toIso8601String()}] CPU μs: $cpuMicros';

    if (previousMicros != null && previousTime != null) {
      final microsDelta = cpuMicros - previousMicros!;
      final intervalMicros = now.difference(previousTime!).inMicroseconds;
      final millicores = ((microsDelta / intervalMicros) * 1000).round();

      output += ' | delta: +$microsDelta | CPU: ${millicores}m';

      if (cpuLimitMillicores != null && cpuLimitMillicores > 0) {
        final percentage = (millicores / cpuLimitMillicores) * 100;
        output += ' (${percentage.toStringAsFixed(1)}%)';
      }
    }

    print(output);
    previousMicros = cpuMicros;
    previousTime = now;
  });

  if (burnMode) _startBurnLoad();
}

void _startBurnLoad() {
  () async {
    var phase = 0.0;
    while (true) {
      final cycleStart = DateTime.now();
      phase += 0.05;
      final intensity = 0.2 + 0.8 * ((1 + sin(phase)) / 2);
      final burnMs = (1000 * intensity).round();
      final burnEnd = cycleStart.add(Duration(milliseconds: burnMs));

      while (DateTime.now().isBefore(burnEnd)) {
        var sum = 0.0;
        for (var i = 0; i < 100000; i++) {
          sum += i * 0.001;
        }
      }

      final elapsed = DateTime.now().difference(cycleStart).inMilliseconds;
      final sleepMs = 1000 - elapsed;
      if (sleepMs > 0) await Future.delayed(Duration(milliseconds: sleepMs));
    }
  }();
}
