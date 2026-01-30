#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>

int32_t get_cgroup_version() {
    FILE *fp = fopen("/sys/fs/cgroup/cpu.stat", "r");
    if (fp) { fclose(fp); return 2; }
    fp = fopen("/sys/fs/cgroup/cpuacct/cpuacct.usage", "r");
    if (fp) { fclose(fp); return 1; }
    return 0;
}

int64_t get_cpu_usage_micros() {
    FILE *fp;
    char buffer[256];
    int64_t micros = 0;

    fp = fopen("/sys/fs/cgroup/cpu.stat", "r");
    if (fp) {
        while (fgets(buffer, sizeof(buffer), fp)) {
            if (strncmp(buffer, "usage_usec", 10) == 0) {
                sscanf(buffer, "usage_usec %" PRId64, &micros);
                break;
            }
        }
        fclose(fp);
        if (micros > 0) return micros;
    }

    fp = fopen("/sys/fs/cgroup/cpuacct/cpuacct.usage", "r");
    if (fp) {
        int64_t nanos = 0;
        if (fscanf(fp, "%" PRId64, &nanos) == 1) {
            micros = nanos / 1000;
        }
        fclose(fp);
    }
    return micros;
}

int32_t get_cpu_limit_millicores() {
    FILE *fp;

    fp = fopen("/sys/fs/cgroup/cpu.max", "r");
    if (fp) {
        char quota_str[64], period_str[64];
        if (fscanf(fp, "%63s %63s", quota_str, period_str) == 2) {
            fclose(fp);
            if (strcmp(quota_str, "max") == 0) return -1;
            int64_t quota = atoll(quota_str);
            int64_t period = atoll(period_str);
            if (period > 0) return (int32_t)((quota * 1000) / period);
        } else {
            fclose(fp);
        }
    }

    const char *quota_paths[] = {
        "/sys/fs/cgroup/cpu/cpu.cfs_quota_us",
        "/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_quota_us"
    };
    const char *period_paths[] = {
        "/sys/fs/cgroup/cpu/cpu.cfs_period_us",
        "/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_period_us"
    };

    for (int i = 0; i < 2; i++) {
        FILE *fp_quota = fopen(quota_paths[i], "r");
        FILE *fp_period = fopen(period_paths[i], "r");
        if (fp_quota && fp_period) {
            int64_t quota, period;
            if (fscanf(fp_quota, "%" PRId64, &quota) == 1 &&
                fscanf(fp_period, "%" PRId64, &period) == 1) {
                fclose(fp_quota);
                fclose(fp_period);
                if (quota == -1) return -1;
                if (period > 0) return (int32_t)((quota * 1000) / period);
            }
        }
        if (fp_quota) fclose(fp_quota);
        if (fp_period) fclose(fp_period);
    }

    return -1;
}
