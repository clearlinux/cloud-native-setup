# Metric testing for scaling on Kubernetes.

This folder contains tools to aid in measuring the scaling capabilities of
Kubernetes clusters.

The tools tend to take one of two forms:

- Tools to take measurements
- Tools to analyse results

For more details, see individual sub-folders. A brief summary of available tools
is below:

| Tool | Description |
| ---- | ----------- |
| collectd | `collectd` based statistics/metrics gathering daemonset code |
| lib | General library helper functions for forming and launching workloads, and storing results in a uniform manner to aid later analysis |
| report | Rmarkdown based report generator, used to produce a PDF comparison report of 1 or more sets of results |
| scaling | Tests to measure scaling, such as linear or parallel launching of pods |


## Results storage and analysis

The tools generate JSON formatted results files via the `lib/json.bash` functions. The `metrics_json_save()`
function in that file has the ability to also `curl` or `socat` the JSON results to a database defined
by environment variables (see the file source for details). This method has been used to store results in
Elasticsearch and InfluxDB databases for instance, but should be adaptable to use with any REST API that accepts
JSON input.

## Scaling execution
This section describes a complete step-by-step scaling execution up to results reporting by using `scaling/k8s_scale.sh` tool which launches a series of workloads and take memory metric measurements after each launch.

**Requirements**
* A Kubernetes cluster up and running (tested on v1.15.3).
* `bc` and `jq` packages.
* Docker (only for report generation).

The steps to execute a run of the scaling framework are listed below, which need to be executed on the master node of a Kubernetes cluster to avoid network issues:
1. Clone `cloud-native-setup` repository into a preferred directory and change directory up to `cloud-native-setup/metrics`:
   ```sh
   $ git clone https://github.com/clearlinux/cloud-native-setup.git
   $ cd cloud-native-setup/metrics
   ```
2. Launch the execution by:
   ```sh
   $ ./scaling/k8s_scale.sh
   INFO: Initialising
   command: bc: yes
   command: jq: yes
   INFO: Checking Kubernetes accessible
   INFO: 1 Kubernetes nodes in 'Ready' state found
   starting kubectl proxy
   Starting to serve on 127.0.0.1:8090
   daemonset.apps/stats created
   Waiting for daemon set "stats" rollout to finish: 0 of 1 updated pods are available...
   daemon set "stats" successfully rolled out
   INFO: Running test
   INFO: And grab some stats
   INFO: idle [98.49] free [29031100] launch [0] node [clr-30f01b5149ba4ab8b05a7ee03b6812a5] inodes_free [31103039]
   INFO: Testing replicas 1 of 20
   INFO: Content of runtime_command=:/@RUNTIMECLASS@/d
   ...
   ```
The above execution might take about 4min because it launch up to 20 pods by default and takes measurements for CPU utilization, memory utilization and pod boot time, finally it will generate a `k8s-scaling.json` result file at `result` directory.

**Note**: to test the launch of pods concurrently, `k8s_parallel.sh` may be used. For quicker testing, `k8s_scale_rapid.sh` can be used in place of `k8s_scale.sh`. The rest of the launch instructions remain consistent other than script name.

**Note**: by default the scaling framework makes call to the Kubernetes API directly so, if facing connectivity issues verify that `kubelet` service's proxies and `no_proxy` environment variable are properly setup.

**Note**: by default the scaling framework uses default values for all its required variables, which can be checked through `scaling/k8s_scale.sh -h` and updated when launching the execution, i.e.:
```
$ ./scaling/k8s_scale.sh -h
Usage: ./scaling/k8s_scale.sh [-h] [options]
   Description:
	Launch a series of workloads and take memory metric measurements after
	each launch.
   Options:
		-h,    Help page.

Environment variables:
	Name (default)
		Description
	TEST_NAME (k8s scaling)
		Can be set to over-ride the default JSON results filename
	NUM_PODS (20)
		Number of pods to launch
	STEP (1)
		Number of pods to launch per cycle
	wait_time (30)
		Seconds to wait for pods to become ready
	delete_wait_time (600)
		Seconds to wait for all pods to be deleted
	settle_time (5)
		Seconds to wait after pods ready before taking measurements
	use_api (yes)
		specify yes or no to use the API to launch pods
	grace (30)
		specify the grace period in seconds for workload pod termination

$ use_api=no ./scaling/k8s_scale.sh
```

The steps to generate the result report are listed below:

1. Having the `results/k8s-scaling.json` result file, create a subdirectory in the `results` directory with a preferred name and copy the `k8s-scaling.json` file into it, so the file distribution looks like:
   ```sh
   $ tree result
   results/
   └── scaling
       └── k8s-scaling.json
   ```

**Note**: if `k8s_scale_rapid.sh` was run instead of `k8s_scale.sh`, that the `<node_name>.tar.gz` files that appear in the results directory also need to be copied into the newly created subdirectory. And the results file is named `k8s-rapid.json` rather than `k8s-scaling.json`.
If k8s_parallel.sh was run, the results file is named `k8s-parallel.json` rather than `k8s-scaling.json`.

2. Launch the report generation by:
   ```sh
   ./report/makereport.sh
   ```
   **Note**: the first time you launch the report generation it will build a docker container to generate the reports and this process can take several minutes. Subsequent runs will be much faster.

   The above execution will generate a `report/output` directory with the final reports, such as:
   ```sh
   $ tree report/output/
   report/output/
   ├── dut-1.png
   ├── metrics_report.pdf
   ├── scaling-1.png
   ├── scaling-2.png
   ├── scaling-3.png
   └── scaling-4.png
   ```
More details about result reporting can be reviewed at [`report`](./report) directory.

# Developers

This section provides some details of how the code is structured and configured. This may be of use whilst modifying
existing or creating new tests.

## Metrics gathering

Metrics can be gathered using either a daemonset deployment of privileged pods used to gather statistics directly from the nodes using a combination of `mpstat`, `free` and `df`, or a daemonset deployment based around `collectd`.

### `collectd` statistics

The `collected` based code can be found in the `collectd` subdirectory. It uses the `collected` configuration found in the `collectd.conf` file to gather statistics, and store the results on the nodes themselves whilst tests are running. At the end of the test, the results are copied from the nodes and stored in the results directory for later processing.

The `collectd` statistics are only configured and gathered if the environment variable `SMF_USE_COLLECTD` is set to non-empty by the test code (that is, only enabled upon request).

### privileged statistics pods

The privileged statistics pods `YAML` can be found in the `scaling/stats.yaml` file. An example of how to invoke and use this daemonset to extract statistics can be found in the `scaling/k8s_scale.sh` file.
