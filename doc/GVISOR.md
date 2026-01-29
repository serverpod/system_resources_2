# gVisor Compatibility Guide

This document describes how the `system_resources_2` library behaves in gVisor environments.

## Summary

**CPU monitoring is not supported in gVisor.** Use external monitoring solutions (Prometheus, Kubernetes metrics) for CPU usage.

**Memory monitoring works correctly** in gVisor.

## Compatibility Table

| Feature | Standard Container | gVisor Container |
|---------|-------------------|------------------|
| Container detection | Works (cgroups v2) | Returns `false` |
| CPU load average | Works | **Not supported (returns 0)** |
| CPU limit | Auto-detected | Returns host cores |
| Memory limit | Auto-detected | Works (virtualized `/proc/meminfo`) |
| Memory usage | Accurate | Works correctly |

## Why gVisor Behaves Differently

gVisor is a sandboxed container runtime that implements its own Linux-compatible kernel in userspace. This affects how system information is exposed:

### What gVisor Virtualizes

| Resource | gVisor Behavior |
|----------|-----------------|
| `/proc/meminfo` | Virtualized to show container memory limit |
| `/proc/self/stat` | Available |
| `/proc/uptime` | Available |

### What gVisor Does NOT Virtualize

| Resource | gVisor Behavior |
|----------|-----------------|
| `/sys/fs/cgroup/*` | Not exposed |
| `getloadavg()` | Returns 0 |
| `/proc/stat` | Returns all zeros |
| `/proc/cpuinfo` | Shows host CPU count |

## Detailed Findings

### Memory Detection (Works)

gVisor virtualizes `/proc/meminfo` to reflect container memory limits:

| Source | Value in gVisor | Expected | Accurate? |
|--------|-----------------|----------|-----------|
| `/proc/meminfo` MemTotal | 262144 kB (256 MB) | 256Mi | **Yes** |

The library's memory functions work correctly in gVisor without any configuration.

### CPU Limit Detection

gVisor does not expose cgroups, so CPU limit cannot be auto-detected. The library returns host CPU count instead of container limit:

| Source | Value in gVisor | Expected | Accurate? |
|--------|-----------------|----------|-----------|
| `/proc/cpuinfo` processors | 2 (host) | 1 (limit) | **No** |
| `nproc` | 2 (host) | 1 (limit) | **No** |

### CPU Load Average (Not Supported)

**Warning:** `cpuLoadAvg()` always returns 0 in gVisor.

gVisor does not virtualize the `getloadavg()` syscall. There is no workaround within this library.

**For CPU usage monitoring in gVisor, use external solutions:**
- Prometheus with cAdvisor
- Kubernetes Metrics API (`kubectl top`)
- Cloud provider monitoring (e.g., Google Cloud Monitoring)

## Live Test Results

Tested on GKE cluster with gVisor runtime.

### Test Configuration

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1"
    memory: "256Mi"
```

### Results Comparison

| Metric | kubectl top (actual) | Library Output |
|--------|---------------------|----------------|
| CPU Usage | 950-976m (~97%) | 0% (not supported) |
| CPU Limit | 1000m (1 core) | 2.00 cores (host value) |
| Memory Limit | 256Mi | 256 MB (correct) |
| Memory Used | 163Mi | 102 MB (different calculation) |

### Key Observations

1. **CPU load** always returns 0 regardless of actual usage (~97% actual load) - not supported
2. **CPU limit** returns host cores instead of container limit
3. **Memory limit** works correctly via gVisor's virtualized `/proc/meminfo`
4. **Memory usage** differs slightly due to calculation methods (library excludes buffers/cached)

## Recommendations for gVisor

1. **Use memory monitoring** - Works correctly without any configuration
2. **Use external CPU monitoring** - Prometheus, Kubernetes Metrics API, or cloud provider solutions
3. **Don't rely on `cpuLoadAvg()`** - Always returns 0 in gVisor
