/*
 * Container-aware system resources library
 *
 * This library auto-detects container environments using cgroups v2.
 * Requirements:
 * - Kubernetes 1.25+ (cgroups v2 is default)
 * - Non-k8s environments must have cgroups v2 enabled
 * - For gVisor: set SYSRES_CPU_CORES env var (see GVISOR_COMPATIBILITY.md)
 *
 * When running outside a container, host values are returned.
 */

/* CPU functions */
float get_cpu_load();
float get_cpu_limit_cores();

/* Memory functions */
float get_memory_usage();
long long get_memory_limit_bytes();
long long get_memory_used_bytes();

/* Container detection */
int is_container_env();
