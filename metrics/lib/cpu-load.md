# `cpu-load` stack stresser

The `cpu-load` stress functionality of the scaling framework allows you to optionally add a constant CPU stress
load to cluster under test whilst the tests are running. This aids impact analysis of CPU load.

The `cpu-load` functionality utilises the [`stress-ng`](https://kernel.ubuntu.com/git/cking/stress-ng.git/) tool
to generate the CPU load. Some of the configuration parameters are taken directoy from the `stress-ng` command line.

## Configuration

`cpu-load` is configured via a number of environment variables:

| Tool | Description |
| ---- | ----------- |
| collectd | `collectd` based statistics/metrics gathering daemonset code |
| lib | General library helper functions for forming and launching workloads, and storing results in a uniform manner to aid later analysis |
| report | Rmarkdown based report generator, used to produce a PDF comparison report of 1 or more sets of results |
| scaling | Tests to measure scaling, such as linear or parallel launching of pods |

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `SMF_CPU_LOAD_NODES` | Set to non-empty to deploy `cpu-load` stressor | unset (off) |
| `SMF_CPU_LOAD_NODES_NCPU` | Number of stressor threads to launch per node | 0 (one per cpu) |
| `SMF_CPU_LOAD_NODES_PERCENT` | Percentage of CPU to load | unset (100%) |
| `SMF_CPU_LOAD_NODES_LIMIT` | k8s cpu resource limit to set | unset (none) |
| `SMF_CPU_LOAD_NODES_REQUEST` | k8s cpu resource request to set | unset (none) |
| `cpu_load_post_deploy_sleep` | Seconds to sleep for `cpu-load` deployment to settle | 30 |

`SMF_CPU_LOAD_NODES` must be set to a non-empty string to enable the `cpu-load` functionality. `cpu-load` uses
a daemonSet to deploy one `stress-ng` single container pod to each active node in the cluster.


Any of the `SMF_CPU_LOAD_NODES_*` variables can be set, or unset, and the daemonSet pods will be configured
appropriately.

## Examples

The combinations of settings available allow a lot of flexibility. Below are some common example setups:

### 50% CPU load on all cores of all nodes (`stress-ng`)

Here we allow `stress-ng` to spawn workers to cover all the CPUs on each node, but ask it to restrict its
bandwidth use to 50% of the CPU. We do not use the k8s limits.

```bash
export SMF_CPU_LOAD_NODES=true
#export SMF_CPU_LOAD_NODES_NCPU=
export SMF_CPU_LOAD_NODES_PERCENT=50
#export SMF_CPU_LOAD_NODES_LIMIT=999m
#export SMF_CPU_LOAD_NODES_REQUEST=999m
```

### 50% CPU load on 1 un-pinned core of all nodes (k8s `limits`)

Here we set `stress-ng` to run a single worker thread at 100% CPU, but use the k8s resource limits to restrict
actual CPU usage to 50%. Because the k8s limit and request are not whole interger units, if the static policy is
in place on the k8s cluster, the pods will be classified as Guaranteed QoS, but will *not* get pinned to a specific
cpuset.

```bash
export SMF_CPU_LOAD_NODES=true
export SMF_CPU_LOAD_NODES_NCPU=1
export SMF_CPU_LOAD_NODES_PERCENT=100
export SMF_CPU_LOAD_NODES_LIMIT=500m
export SMF_CPU_LOAD_NODES_REQUEST=500m
```

### 50% CPU load pinned to 1 core, on all nodes

Here we set `stress-ng` to run a single worker thread at 50% CPU, and use the k8s resource limits to classify the
pod as Guaranteed, and as we are using whole integer units of CPU resource requests, if the static policy manager is
in play, the thread will be pinned to a single cpu cpuset.

```bash
export SMF_CPU_LOAD_NODES=true
export SMF_CPU_LOAD_NODES_NCPU=1
export SMF_CPU_LOAD_NODES_PERCENT=50
export SMF_CPU_LOAD_NODES_LIMIT=1
export SMF_CPU_LOAD_NODES_REQUEST=1
```

