* [Metric testing for scaling on Kubernetes.](#metric-testing-for-scaling-on-kubernetes)
    * [Results storage and analysis](#results-storage-and-analysis)
* [Developers](#developers)
    * [Metrics gathering](#metrics-gathering)
        * [`collectd` statistics](#collectd-statistics)
        * [privileged statistics pods](#privileged-statistics-pods)
    * [Configuring constant 'loads'](#configuring-constant-loads)

# Metric testing for scaling on Kubernetes.

This folder contains tools to aid in measuring the scaling capabilities of
Kubernetes clusters.

Primarily these tools were designed to measure scaling of large number of pods on a single node, but
the code is structured to handle multiple nodes, and may also be useful in that scenario.

The tools tend to take one of two forms:

- Tools to launch jobs and take measurements
- Tools to analyse results

For more details, see individual sub-folders. A brief summary of available tools
is below:

| Folder | Description |
| ---- | ----------- |
| collectd | `collectd` based statistics/metrics gathering daemonset code |
| lib | General library helper functions for forming and launching workloads, and storing results in a uniform manner to aid later analysis |
| lib/[cpu-load*](lib/cpu-load.md) | Helper functions to enable CPU load generation on a cluster whilst under test |
| [report](report/README.md) | Rmarkdown based report generator, used to produce a PDF comparison report of one or more sets of results |
| [scaling](scaling/README.md) | Tests to measure scaling, such as linear or parallel launching of pods |

## Results storage and analysis

The tools generate JSON formatted results files via the [`lib/json.bash`](lib/json.bash) functions. The `metrics_json_save()`
function has the ability to also `curl` or `socat` the JSON results to a database defined
by environment variables (see the file source for details). This method has been used to store results in
Elasticsearch and InfluxDB databases for instance, but should be adaptable to use with any REST API that accepts
JSON input.

## Prerequisites

There are some basic pre-requisites required in order to run the test and process the results:

* A Kubernetes cluster up and running (tested on v1.15.3).
* `bc` and `jq` packages.
* Docker (only for report generation).

# Developers

Below are some architecture and internal details of how the code is structured and configured. This will be
helpful for improving, modifying or submitting fixes to the code base.

## Metrics gathering

Metrics can be gathered using either a daemonset deployment of privileged pods used to gather statistics
directly from the nodes using a combination of `mpstat`, `free` and `df`, or a daemonset deployment based
around `collectd`. The general recommendation is to use the `collectd` based collection if possible, as it
is more efficient, as the system does not have to poll and wait for results, and thus executes the test
cycle faster. The `collectd` results are collected asyncronously, and the report generator code later
aligns the results with the pod execution in the timeline.

### `collectd` statistics

The `collected` based code can be found in the `collectd` subdirectory. It uses the `collected` configuration
found in the `collectd.conf` file to gather statistics, and store the results on the nodes themselves whilst
tests are running. At the end of the test, the results are copied from the nodes and stored in the results
directory for later processing.

The `collectd` statistics are only configured and gathered if the environment variable `SMF_USE_COLLECTD`
is set to non-empty by the test code (that is, it is only enabled upon request).

### privileged statistics pods

The privileged statistics pods `YAML` can be found in the [`scaling/stats.yaml`](scaling/stats.yaml) file.
An example of how to invoke and use this daemonset to extract statistics can be found in the
[`scaling/k8s_scale.sh`](scaling/k8s_scale.sh) file.

## Configuring constant 'loads'

The framework includes some tooling to assist in setting up constant pre-defined 'loads' across the cluster
to aid evaluation of their impacts on the scaling metrics. See the [cpu-load documentation](lib/cpu-load.md)
for more information.
