#include "sysres.h"

// Linux
#if __unix__

#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>

/*
 * Container-aware memory functions using cgroups v2.
 * Falls back to /proc/meminfo when not in a container.
 *
 * cgroups v2 files used:
 * - /sys/fs/cgroup/memory.max  (limit in bytes, or "max" if unlimited)
 * - /sys/fs/cgroup/memory.current (current usage in bytes)
 *
 * Note: gVisor virtualizes /proc/meminfo to show container limits,
 * so the fallback works correctly in gVisor environments.
 */

static long long get_entry(const char *name, const char *buff)
{
	char *hit = strstr(buff, name);
	if (hit == NULL)
	{
		return 0;
	}
	long long val = strtoll(hit + strlen(name), NULL, 10);
	return val;
}

/* Read a single value from a cgroup file. Returns -1 on failure or if "max". */
static long long read_cgroup_value(const char *path)
{
	FILE *fd = fopen(path, "r");
	if (fd == NULL)
	{
		return -1;
	}

	char buff[64] = {0};
	size_t len = fread(buff, 1, sizeof(buff) - 1, fd);
	fclose(fd);

	if (len == 0)
	{
		return -1;
	}

	/* Check if the value is "max" (unlimited) */
	if (strncmp(buff, "max", 3) == 0)
	{
		return -1;
	}

	return strtoll(buff, NULL, 10);
}

/* Get memory info from /proc/meminfo (host or gVisor virtualized) */
static void get_proc_meminfo(long long *total, long long *used)
{
	FILE *fd;
	char buff[4096] = {0};

	fd = fopen("/proc/meminfo", "r");
	if (fd == NULL)
	{
		*total = 0;
		*used = 0;
		return;
	}

	size_t len = fread(buff, 1, sizeof(buff) - 1, fd);
	fclose(fd);

	if (len == 0)
	{
		*total = 0;
		*used = 0;
		return;
	}

	/* Values in /proc/meminfo are in kB */
	long long total_kb = get_entry("MemTotal:", buff);
	long long free_kb = get_entry("MemFree:", buff);
	long long buffers_kb = get_entry("Buffers:", buff);
	long long cached_kb = get_entry("Cached:", buff);

	*total = total_kb * 1024;  /* Convert to bytes */
	*used = (total_kb - free_kb - buffers_kb - cached_kb) * 1024;
}

/* Check if running in a container with cgroups v2 memory limits */
static int has_cgroup_memory_limit()
{
	long long limit = read_cgroup_value("/sys/fs/cgroup/memory.max");
	return limit > 0;
}

int is_container_env()
{
	return has_cgroup_memory_limit();
}

long long get_memory_limit_bytes()
{
	/* Try cgroups v2 first */
	long long cgroup_limit = read_cgroup_value("/sys/fs/cgroup/memory.max");
	if (cgroup_limit > 0)
	{
		return cgroup_limit;
	}

	/* Fall back to /proc/meminfo (works for host and gVisor) */
	long long total, used;
	get_proc_meminfo(&total, &used);
	return total;
}

long long get_memory_used_bytes()
{
	/* Try cgroups v2 first */
	if (has_cgroup_memory_limit())
	{
		long long current = read_cgroup_value("/sys/fs/cgroup/memory.current");
		if (current >= 0)
		{
			return current;
		}
	}

	/* Fall back to /proc/meminfo calculation */
	long long total, used;
	get_proc_meminfo(&total, &used);
	return used;
}

float get_memory_usage()
{
	long long limit = get_memory_limit_bytes();
	long long used = get_memory_used_bytes();

	if (limit <= 0)
	{
		return 0.0f;
	}

	return (float)used / (float)limit;
}

#endif

// MacOS
#if __MACH__

#include <mach/vm_statistics.h>
#include <mach/mach_types.h>
#include <mach/mach_init.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>

/*
 * macOS does not support containers natively.
 * These functions always return host values.
 */

static void get_macos_memory(long long *total, long long *used)
{
	vm_size_t page_size;
	mach_port_t mach_port;
	mach_msg_type_number_t count;
	vm_statistics64_data_t vm_stats;

	mach_port = mach_host_self();
	count = sizeof(vm_stats) / sizeof(natural_t);

	*used = 0;
	*total = 0;

	if (KERN_SUCCESS == host_page_size(mach_port, &page_size) && KERN_SUCCESS == host_statistics64(mach_port, HOST_VM_INFO, (host_info64_t)&vm_stats, &count))
	{
		long long free_memory = (int64_t)vm_stats.free_count * (int64_t)page_size;
		*used = ((int64_t)vm_stats.active_count + (int64_t)vm_stats.inactive_count + (int64_t)vm_stats.wire_count) * (int64_t)page_size;
		*total = free_memory + *used;
	}
}

int is_container_env()
{
	/* macOS does not support containers natively */
	return 0;
}

long long get_memory_limit_bytes()
{
	long long total, used;
	get_macos_memory(&total, &used);
	return total;
}

long long get_memory_used_bytes()
{
	long long total, used;
	get_macos_memory(&total, &used);
	return used;
}

float get_memory_usage()
{
	long long total, used;
	get_macos_memory(&total, &used);

	if (total == 0)
	{
		return 0.0f;
	}

	return (float)used / (float)total;
}

#endif

// Windows
#if _WIN64

// TODO

#endif
