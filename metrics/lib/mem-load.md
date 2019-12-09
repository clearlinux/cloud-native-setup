# `mem-load` stack stresser

The `mem-load` stress functionality of the scaling framework allows you to optionally add memory stress
load to cluster under test whilst the tests are running. This aids impact analysis of memory load.

The `mem-load` functionality utilises the [`stress-ng`](https://kernel.ubuntu.com/git/cking/stress-ng.git/) tool
to generate the memory load. Some of the configuration parameters are taken directly from the `stress-ng` command line.

## Configuration

`mem-load` is configured via a number of environment variables:

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `SMF_MEM_LOAD_WORKER` | Set to non-empty to deploy `mem-load` stressor | unset (off) |
| `SMF_MEM_LOAD_WORKER_BYTES` | Memory load per worker node, see `stress-ng --vm-bytes BYTES` | unset (80%) |
| `SMF_MEM_LOAD_WORKER_VMS` | Number of hog processes, see `stress-ng --vm WORKERS` | unset (1) |
| `SMF_MEM_LOAD_WORKER_LIMIT` | k8s memory resource limit to set | unset (none) |
| `SMF_MEM_LOAD_WORKER_REQUEST` | k8s memory resource request to set | unset (none) |

`SMF_MEM_LOAD_WORKER` must be set to a non-empty string to enable the
`mem-load` functionality. `mem-load` uses a DaemonSet to deploy one
`stress-ng` single container pod to each worker node in the cluster.
Any of the `SMF_MEM_LOAD_WORKER_*` variables can be set, or unset, and
the DaemonSet pods will be configured appropriately.

Master node memory load is configured in the same way by replacing
`SMF_MEM_LOAD_WORKER` with `SMF_MEM_LOAD_MASTER`.

## Examples

### 80% memory load on all nodes (`stress-ng`)

Run `stress-ng` to consume 80 % of the free memory on both master and
worker nodes:

```bash
export SMF_MEM_LOAD_MASTER=true
export SMF_MEM_LOAD_WORKER=true
```

### 64 GB load on worker node(s)

This configuration reserves 64 GB of memory on every worker node. The
stress-ng pods request 64 GB memory resource. Deploying the DaemonSet
will not finish unless all available workers match the request.

```bash
export SMF_MEM_LOAD_WORKER=true
export SMF_MEM_LOAD_WORKER_BYTES=64G
export SMF_MEM_LOAD_REQUEST=64G
```
