#include "sysres.h"

// Linux
#if __unix__

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysinfo.h>

/*
 * Container-aware CPU functions using cgroups v2.
 * Falls back to host CPU count when not in a container.
 *
 * cgroups v2 file used:
 * - /sys/fs/cgroup/cpu.max (format: "quota period" or "max period")
 *   CPU cores = quota / period (e.g., 200000/100000 = 2 cores)
 *
 * For gVisor environments (which don't expose cgroups):
 * Set SYSRES_CPU_CORES environment variable to override.
 */

/* Get CPU limit from cgroups v2. Returns -1 if not available or unlimited. */
static float get_cgroup_cpu_limit()
{
	FILE *fd = fopen("/sys/fs/cgroup/cpu.max", "r");
	if (fd == NULL)
	{
		return -1.0f;
	}

	char buff[64] = {0};
	size_t len = fread(buff, 1, sizeof(buff) - 1, fd);
	fclose(fd);

	if (len == 0)
	{
		return -1.0f;
	}

	/* Check if quota is "max" (unlimited) */
	if (strncmp(buff, "max", 3) == 0)
	{
		return -1.0f;
	}

	/* Parse "quota period" format */
	long long quota = 0;
	long long period = 0;
	if (sscanf(buff, "%lld %lld", &quota, &period) != 2)
	{
		return -1.0f;
	}

	if (period <= 0)
	{
		return -1.0f;
	}

	return (float)quota / (float)period;
}

/* Get CPU limit from environment variable (for gVisor). Returns -1 if not set. */
static float get_env_cpu_limit()
{
	const char *env_val = getenv("SYSRES_CPU_CORES");
	if (env_val == NULL)
	{
		return -1.0f;
	}

	float cores = strtof(env_val, NULL);
	if (cores <= 0)
	{
		return -1.0f;
	}

	return cores;
}

float get_cpu_limit_cores()
{
	/* Priority 1: Environment variable (for gVisor) */
	float env_limit = get_env_cpu_limit();
	if (env_limit > 0)
	{
		return env_limit;
	}

	/* Priority 2: cgroups v2 */
	float cgroup_limit = get_cgroup_cpu_limit();
	if (cgroup_limit > 0)
	{
		return cgroup_limit;
	}

	/* Fallback: host CPU count */
	return (float)get_nprocs();
}

float get_cpu_load()
{
	double load[1] = {0};
	getloadavg(load, 1);

	float cpu_limit = get_cpu_limit_cores();
	if (cpu_limit <= 0)
	{
		cpu_limit = (float)get_nprocs();
	}

	return (float)load[0] / cpu_limit;
}

#endif

#if __MACH__

#include <stdlib.h>
#include <sys/types.h>
#include <sys/sysctl.h>

/*
 * macOS does not support containers natively.
 * These functions always return host values.
 */

static int get_macos_cpu_count()
{
	int thread_count;
	size_t len = sizeof(thread_count);
	sysctlbyname("machdep.cpu.thread_count", &thread_count, &len, NULL, 0);
	return thread_count;
}

float get_cpu_limit_cores()
{
	return (float)get_macos_cpu_count();
}

float get_cpu_load()
{
	double load[1] = {0};
	getloadavg(load, 1);
	return load[0] / get_macos_cpu_count();
}

#endif

// Windows
#if _WIN64

// TODO

#endif
