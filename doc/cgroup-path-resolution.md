# Cgroup Path Resolution

## Problem

On native Linux hosts running systemd with cgroup v2, memory metrics
(`memoryLimitBytes`, `memoryUsedBytes`, `memUsage`) returned **zero**.

The CI showed this clearly: `test-linux (amd64)` and `test-linux (arm64)` both
failed with `memoryLimitBytes` returning 0, while `test-container (amd64)` and
`test-container (arm64)` passed.

## Root Cause

The library hardcoded cgroup file paths at the filesystem root:

```
/sys/fs/cgroup/memory.max
/sys/fs/cgroup/memory.current
```

On Ubuntu 24.04 with systemd cgroup v2:

- `/sys/fs/cgroup/cpu.stat` **exists** at the root cgroup (so the platform was
  correctly detected as `linuxCgroupV2`), and CPU metrics worked.
- `/sys/fs/cgroup/memory.max` and `memory.current` do **not** exist at the root
  cgroup. They live in child cgroup slices managed by systemd (e.g.,
  `/sys/fs/cgroup/user.slice/user-1001.slice/session-1.scope/`).

In containers, Docker creates a **cgroup namespace** where the process is at the
root of its own namespace. `/proc/self/cgroup` contains `0::/`, so the root path
(`/sys/fs/cgroup/`) is correct and the memory files are present. This is why the
container tests always passed.

## How Major Runtimes Solve This

Every major runtime resolves the process's **actual cgroup path** from
`/proc/self/cgroup` rather than hardcoding the root path.

### JDK (OpenJDK)

Source: `src/hotspot/os/linux/cgroupSubsystem_linux.cpp`

1. Reads `/proc/self/cgroup` to find the v2 entry (hierarchy-ID `0`).
2. Reads `/proc/self/mountinfo` to find the cgroup2 mount point.
3. Joins `mount_path + cgroup_path` via `CgroupV2Controller::construct_path()`.
4. Reads controller files (`memory.max`, `memory.current`, `cpu.stat`, etc.)
   from that resolved directory.

### .NET Runtime

Source: `src/libraries/Common/src/Interop/Linux/cgroups/Interop.cgroups.cs`

1. `FindCGroupPath()` combines:
   - `hierarchyMount` from `/proc/self/mountinfo` (e.g., `/sys/fs/cgroup`)
   - `hierarchyRoot` from `/proc/self/mountinfo`
   - `cgroupPathRelativeToMount` from `/proc/self/cgroup`
2. For cgroup v2 memory limits, it **walks up the hierarchy** from the process's
   cgroup to the mount root, checking `memory.max` at each level and taking the
   minimum. This handles nested cgroup limits correctly.

### Go — uber-go/automaxprocs

Source: `internal/cgroups/cgroups2.go` and `internal/cgroups/subsys.go`

1. Reads `/proc/self/cgroup`, finds the entry with ID `0`.
2. Constructs `mountPoint + groupPath + file`
   (e.g., `/sys/fs/cgroup/user.slice/.../cpu.max`).

### cadvisor (Google)

Source: `container/common/helpers.go`

1. Uses `GetControllerPath(cgroupPaths, "memory", cgroup2UnifiedMode)` to look
   up per-controller paths.
2. Checks `utils.FileExists(path.Join(memoryRoot, "memory.max"))` before reading.

## What We Changed

### 1. Dynamic cgroup v2 path resolution (`cgroup_detector.dart`)

Added `resolveCgroupDir()` which reads `/proc/self/cgroup`, finds the `0::$PATH`
entry, and constructs the full directory path:

```
/sys/fs/cgroup + $PATH
```

- In containers: `0::/` resolves to `/sys/fs/cgroup/`
- On native hosts: `0::/user.slice/.../session.scope` resolves to the directory
  where memory controller files actually reside.

The cgroup v2 path constants (`cgroupV2CpuStat`, `cgroupV2MemoryMax`, etc.) were
converted from `static const` to `static get` so they use the resolved directory.

### 2. `/proc/meminfo` fallback (`cgroup_memory.dart`)

Even with path resolution, the cgroup memory files may not exist (e.g., on
unusual kernel configurations). The four cgroup memory reader methods now fall
back to `/proc/meminfo` instead of returning 0:

| Method             | Fallback                                  |
| ------------------ | ----------------------------------------- |
| `readV2LimitBytes` | `readProcMemTotal()` (MemTotal)           |
| `readV2UsedBytes`  | `readProcMemUsed()` (MemTotal - MemAvail) |
| `readV1LimitBytes` | `readProcMemTotal()`                      |
| `readV1UsedBytes`  | `readProcMemUsed()`                       |

This is consistent with the existing behavior when `memory.max` contains `"max"`
(unlimited), which already fell back to `readProcMemTotal()`.

## Why We Don't Parse `/proc/self/mountinfo`

Unlike the JDK and .NET, we skip parsing `/proc/self/mountinfo` and assume the
standard cgroup v2 mount point `/sys/fs/cgroup`. This is a pragmatic
simplification: on every modern Linux distribution with systemd (Ubuntu, Fedora,
Debian, RHEL, SLES), the unified cgroup v2 hierarchy is always mounted at
`/sys/fs/cgroup`. The JDK and .NET parse mountinfo primarily for compatibility
with exotic mount configurations and hybrid v1+v2 setups, which are increasingly
rare.

If a non-standard mount point is ever needed, `resolveCgroupDir()` can be
extended to parse `/proc/self/mountinfo` at that time.
