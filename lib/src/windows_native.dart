import 'dart:ffi';

import 'package:ffi/ffi.dart' as ffi;
import 'dart:io';

/// FFI bindings for Windows system APIs.
///
/// This provides system resource monitoring on Windows using kernel32.dll,
/// which is always available on every Windows installation. On Linux, pure
/// Dart implementations are used instead, and macOS uses the libsysres
/// native library.

/// Native signature of `GetSystemTimes`.
typedef GetSystemTimesNative = Int32 Function(
  Pointer<FileTime> idleTime,
  Pointer<FileTime> kernelTime,
  Pointer<FileTime> userTime,
);

typedef GetSystemTimesDart = int Function(
  Pointer<FileTime> idleTime,
  Pointer<FileTime> kernelTime,
  Pointer<FileTime> userTime,
);

/// Native signature of `GlobalMemoryStatusEx`.
typedef GlobalMemoryStatusExNative = Int32 Function(
  Pointer<MemoryStatusEx> buffer,
);

typedef GlobalMemoryStatusExDart = int Function(
  Pointer<MemoryStatusEx> buffer,
);

/// The `FILETIME` structure, a 64-bit value representing the number of
/// 100-nanosecond intervals since January 1, 1601 (UTC).
///
/// See https://learn.microsoft.com/windows/win32/api/minwinbase/ns-minwinbase-filetime
final class FileTime extends Struct {
  @Uint32()
  external int dwLowDateTime;

  @Uint32()
  external int dwHighDateTime;

  /// The full value in 100-nanosecond intervals.
  int get value => (dwHighDateTime << 32) | dwLowDateTime;
}

/// The `MEMORYSTATUSEX` structure returned by `GlobalMemoryStatusEx`.
///
/// See https://learn.microsoft.com/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex
final class MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;

  @Uint32()
  external int dwMemoryLoad;

  @Uint64()
  external int ullTotalPhys;

  @Uint64()
  external int ullAvailPhys;

  @Uint64()
  external int ullTotalPageFile;

  @Uint64()
  external int ullAvailPageFile;

  @Uint64()
  external int ullTotalVirtual;

  @Uint64()
  external int ullAvailVirtual;

  @Uint64()
  external int ullAvailExtendedVirtual;
}

/// Windows native wrapper for system resources.
///
/// Loads kernel32.dll lazily on first use; no explicit initialization is
/// required.
class WindowsNative {
  static GetSystemTimesDart? _getSystemTimes;
  static GlobalMemoryStatusExDart? _globalMemoryStatusEx;

  // CPU state for delta calculation, in 100-nanosecond intervals.
  static int? _lastBusyTime;
  static int? _lastTotalTime;

  /// Looks up `GetSystemTimes` in kernel32.dll on first use.
  ///
  /// Returns `null` if the lookup fails (never expected on Windows).
  static GetSystemTimesDart? _resolveGetSystemTimes() {
    if (!Platform.isWindows) return null;
    return _getSystemTimes ??= DynamicLibrary.open('kernel32.dll')
        .lookupFunction<GetSystemTimesNative, GetSystemTimesDart>(
      'GetSystemTimes',
    );
  }

  /// Looks up `GlobalMemoryStatusEx` in kernel32.dll on first use.
  ///
  /// Returns `null` if the lookup fails (never expected on Windows).
  static GlobalMemoryStatusExDart? _resolveGlobalMemoryStatusEx() {
    if (!Platform.isWindows) return null;
    return _globalMemoryStatusEx ??= DynamicLibrary.open('kernel32.dll')
        .lookupFunction<GlobalMemoryStatusExNative, GlobalMemoryStatusExDart>(
      'GlobalMemoryStatusEx',
    );
  }

  /// Get CPU load as the fraction of total CPU capacity in use.
  ///
  /// Windows does not expose a load average. Instead, the busy time across
  /// all cores is compared between calls: the returned value is the share of
  /// CPU time that was busy since the previous call, where 1.0 means all
  /// cores were fully busy.
  ///
  /// The first call initializes the baseline and returns 0.0. For accurate
  /// readings, wait at least 100ms between calls.
  static double cpuLoadAvg() {
    final getSystemTimes = _resolveGetSystemTimes();
    if (getSystemTimes == null) return 0.0;

    final idle = ffi.calloc<FileTime>();
    final kernel = ffi.calloc<FileTime>();
    final user = ffi.calloc<FileTime>();

    try {
      final result = getSystemTimes(idle, kernel, user);
      if (result == 0) return 0.0;

      // Kernel time includes idle time.
      final busyTime = kernel.ref.value + user.ref.value - idle.ref.value;
      final totalTime = kernel.ref.value + user.ref.value;

      final lastBusyTime = _lastBusyTime;
      final lastTotalTime = _lastTotalTime;
      _lastBusyTime = busyTime;
      _lastTotalTime = totalTime;

      if (lastBusyTime == null || lastTotalTime == null) return 0.0;

      final busyDelta = busyTime - lastBusyTime;
      final totalDelta = totalTime - lastTotalTime;
      if (totalDelta <= 0) return 0.0;

      return (busyDelta / totalDelta).clamp(0.0, 1.0);
    } finally {
      ffi.calloc.free(idle);
      ffi.calloc.free(kernel);
      ffi.calloc.free(user);
    }
  }

  /// Get the total physical memory in bytes.
  static int memoryLimitBytes() {
    final globalMemoryStatusEx = _resolveGlobalMemoryStatusEx();
    if (globalMemoryStatusEx == null) return 0;

    final buffer = ffi.calloc<MemoryStatusEx>()
      ..ref.dwLength = sizeOf<MemoryStatusEx>();

    try {
      final result = globalMemoryStatusEx(buffer);
      if (result == 0) return 0;
      return buffer.ref.ullTotalPhys;
    } finally {
      ffi.calloc.free(buffer);
    }
  }

  /// Get the physical memory currently in use, in bytes.
  static int memoryUsedBytes() {
    final globalMemoryStatusEx = _resolveGlobalMemoryStatusEx();
    if (globalMemoryStatusEx == null) return 0;

    final buffer = ffi.calloc<MemoryStatusEx>()
      ..ref.dwLength = sizeOf<MemoryStatusEx>();

    try {
      final result = globalMemoryStatusEx(buffer);
      if (result == 0) return 0;
      return buffer.ref.ullTotalPhys - buffer.ref.ullAvailPhys;
    } finally {
      ffi.calloc.free(buffer);
    }
  }

  /// Clears the CPU delta state. Useful for testing.
  static void clearState() {
    _lastBusyTime = null;
    _lastTotalTime = null;
  }
}
