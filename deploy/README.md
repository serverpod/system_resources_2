# Cgroup-Based CPU Monitor for gVisor Containers

A Dart-based CPU monitor that accurately measures container CPU usage by reading cgroup metrics directly.

## The Problem

The naive approach of reading `/proc/self/stat` fails in containerized environments:

- **Only tracks the monitor process itself** - misses CPU consumed by child processes, Dart isolates, garbage collection, and other container processes
- **Discrepancy with orchestrator metrics** - `kubectl top` reports container-wide usage, while `/proc/self/stat` only sees one process
- **Incomplete picture** - in a multi-process container, you might see 5m while the actual container uses 500m

## The Solution: Cgroup Metrics

Cgroups (control groups) aggregate CPU usage for ALL processes in a container:

- **Same source as `kubectl top`** - both read from cgroup accounting
- **Complete container view** - includes all child processes, isolates, system threads
- **Two versions exist**: v1 (legacy) and v2 (modern unified hierarchy)

## How It Works

### Cgroup v2 (Modern)

Path: `/sys/fs/cgroup/cpu.stat`

```
usage_usec 123456789
user_usec 100000000
system_usec 23456789
```

The `usage_usec` line contains total CPU time in **microseconds**.

### Cgroup v1 (Legacy)

Path: `/sys/fs/cgroup/cpuacct/cpuacct.usage`

Contains total CPU time in **nanoseconds** (divide by 1000 for microseconds).

### Millicores Calculation

```
millicores = (delta_cpu_micros / interval_micros) * 1000
```

Where:
- `delta_cpu_micros` = CPU microseconds consumed since last sample
- `interval_micros` = wall-clock microseconds since last sample
- Result in millicores (1000m = 1 full CPU core)

## Verification Results

Tested in GKE with gVisor (runsc) runtime:

| Condition | Monitor Output | kubectl top | Match |
|-----------|---------------|-------------|-------|
| Idle | 0-5m | 0-5m | ✓ |
| Burn load | 70-130m | ~120m | ✓ (±20%) |

The variance under load is expected due to:
- Different sampling intervals
- Timing of measurements
- GC pauses and isolate scheduling

## Usage

### Build

```bash
dart compile exe main.dart -o cpu_monitor
```

### Deploy

The Dockerfile handles compilation. Deploy with:

```bash
kubectl apply -f deployment.yaml
```

### Flags

- `--burn` - Enable CPU burn mode for testing (generates ~100m load)

### View Logs

```bash
kubectl logs -f deployment/dart-cpu-monitor
```

Example output:
```
--- Dart CPU Monitor started (cgroup metrics) ---
Cgroup version: v2
[2025-01-30T10:00:00.000Z] CPU μs: 1234567 | delta: +50000 | CPU: 25m
```

## References

- [Kernel cgroup v2 documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html) - Official Linux kernel docs on cgroup v2 CPU controller
- [Kubernetes metrics-server](https://github.com/kubernetes-sigs/metrics-server) - How `kubectl top` gets its metrics
- [cAdvisor](https://github.com/google/cadvisor) - Container metrics collector that reads cgroup stats
- [gVisor runsc](https://gvisor.dev/docs/user_guide/compatibility/linux/cgroups/) - gVisor cgroup compatibility
