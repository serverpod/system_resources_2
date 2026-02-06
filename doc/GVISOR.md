# gVisor Compatibility Guide

This document describes how the `system_resources_2` library behaves in gVisor environments.

## Summary

This version uses **cgroup CPU accounting** instead of `getloadavg()`, which may provide better gVisor compatibility depending on your gVisor configuration.

| Feature | Standard Container | gVisor (cgroups exposed) | gVisor (cgroups not exposed) |
|---------|-------------------|--------------------------|------------------------------|
| CPU load | Works | Works | Returns 0 |
| CPU limit | Auto-detected | Auto-detected | Uses `SYSRES_CPU_CORES` env or host cores |
| Memory limit | Auto-detected | Works (virtualized) | Works (virtualized) |
| Memory usage | Works | Works | Works |
| Container detection | Works | Works | Returns `false` |

## How This Version Differs

### Previous Approach (getloadavg)
The original implementation used the `getloadavg()` syscall, which gVisor does **not** virtualize. This always returned 0 in gVisor.

### New Approach (cgroup accounting)
This version reads CPU usage from cgroup files:
- `/sys/fs/cgroup/cpu.stat` (cgroups v2) - reads `usage_usec`
- `/sys/fs/cgroup/cpuacct/cpuacct.usage` (cgroups v1) - reads nanoseconds

This measures **actual CPU time consumed** by the container, not load average.

## gVisor Cgroup Support

Whether cgroup files are exposed depends on your gVisor configuration:

### GKE Autopilot / Managed gVisor
Some managed gVisor environments expose cgroup files. Check if these exist in your container:
```bash
ls /sys/fs/cgroup/cpu.stat
ls /sys/fs/cgroup/cpuacct/cpuacct.usage
```

### Self-managed gVisor
Configure gVisor to expose cgroups by enabling the cgroupfs option. See [gVisor cgroup documentation](https://gvisor.dev/docs/user_guide/compatibility/linux/cgroups/).

## Fallback Behavior

If cgroup files are not available, the library falls back gracefully:

| Metric | Behavior without cgroups |
|--------|-------------------------|
| `cpuLoadAvg()` | Returns 0 |
| `cpuLimitCores()` | Returns `SYSRES_CPU_CORES` env var, or host CPU count |
| `memUsage()` | Works (uses `/proc/meminfo`) |
| `memoryLimitBytes()` | Works (uses `/proc/meminfo` MemTotal) |
| `memoryUsedBytes()` | Works (uses `/proc/meminfo` calculation) |

## Workaround: SYSRES_CPU_CORES Environment Variable

For gVisor environments where cgroups are not exposed, you can manually set the CPU limit:

```yaml
# Kubernetes deployment
env:
  - name: SYSRES_CPU_CORES
    value: "0.5"  # Match your container's CPU limit
```

This allows `cpuLimitCores()` to return the correct value even without cgroup detection.

## Memory Monitoring

**Memory monitoring works correctly** in all gVisor configurations.

gVisor virtualizes `/proc/meminfo` to reflect container memory limits:

| Source | gVisor Behavior |
|--------|-----------------|
| `/proc/meminfo` MemTotal | Shows container memory limit |
| `/proc/meminfo` MemAvailable | Shows available memory |

## Testing in gVisor

```dart
import 'package:system_resources_2/system_resources_2.dart';

void main() async {
  await SystemResources.init();

  print('Container: ${SystemResources.isContainerEnv()}');
  print('Cgroup version: ${SystemResources.cgroupVersion()}');

  // If cgroupVersion is none, cgroups are not exposed
  if (SystemResources.cgroupVersion() == CgroupVersion.none) {
    print('Warning: Cgroups not detected. CPU monitoring may not work.');
    print('Set SYSRES_CPU_CORES env var for accurate CPU limit.');
  }

  // Memory always works
  print('Memory: ${SystemResources.memUsage() * 100}%');
  print('Memory limit: ${SystemResources.memoryLimitBytes()} bytes');
}
```

## Recommendations

1. **Check cgroup availability** - Use `cgroupVersion()` to detect if cgroups are exposed
2. **Set SYSRES_CPU_CORES** - For gVisor without cgroups, set this env var to your CPU limit
3. **Memory monitoring works** - No special configuration needed
4. **Consider external monitoring** - For production, use Prometheus/kubectl top as a backup

## External Monitoring Alternatives

If cgroup-based monitoring doesn't work in your gVisor environment:
- **Prometheus with cAdvisor** - Container metrics from host perspective
- **Kubernetes Metrics API** - `kubectl top pod`
- **Cloud provider monitoring** - GCP Cloud Monitoring, AWS CloudWatch, etc.
