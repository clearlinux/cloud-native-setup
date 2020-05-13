# Scaling metrics tests

This directory contains a number of scripts to perform a variety of system scaling tests.

The tests are described in their individual sections below.

Each test has a number of configurable options. Many of those options are common across all tests.
Those options are detailed in their own section below.

> **Note:** `k8s_scale_rapid.sh` is the most complete and upto date test. It is the only test to
> currently use the `collectd` data collection method. Other tests use a privileged container to
> gather statistics.
>
> If you find one of the other tests useful, please consider updating it and the corresponding report
> generation code to use the `collectd` method and send a Pull Request with your updates to this codebase.

## Global test configuration options

The following variables are settable for many of the tests. Check each individual tests help
for specifics and their individual default values.

| Variable | Default Value | Description |
| -------- | ------------- | ----------- |
| TEST_NAME | test dependant | Can be set to over-ride the default JSON results filename |
| NUM_PODS | 20 | Number of pods to launch |
| STEP | 1 | Number of pods to launch per cycle |
| wait_time | 30 | Seconds to wait for pods to become ready |
| delete_wait_time | 600 | Seconds to wait for all pods to be deleted |
| settle_time | 5 | Seconds to wait after pods ready before taking measurements |
| use_api | yes | specify yes or no to use the JSON API to launch pods (otherwise, launch via YAML) |
| grace | 30 | specify the grace period in seconds for workload pod termination |
| RUNTIME | unset | specify the `RuntimeClass` to use to launch the pods |

## k8s_parallel.sh

Measures pod create and delete times whilst increasing the number of pods launched in parallel.

The test works by creating and destroying deployments with the required number of replicas being scaled.

## k8s_scale_nc.sh

Measures pod response time using `nc` to test network connection response. Stores results as percentile
values. Is used to see if the response time latency and jitter is affected by scaling the number of pods.

## k8s_scale_net.sh

Measures pod response time to a `curl` HTTP get request from the K8S e2e `agnhost` image.
Used to measure if the 'ready to respond' time scales with the number of service ports in use.

## k8s_scale_rapid.sh

Measures how pod launch and the k8s system scales whilst launching more and more pods.

Uses the `collectd` method to gather a number of statistics, including:

- cpu usage
- memory usage
- network connections
- disk usage
- ipc stats

## k8s_scale.sh

The fore-runner to `k8s_scale_rapid.sh`, using the privileged pod method to gather statistics. It is recommended
to use `k8s_scale_rapid.sh` in preference if possible.

# Example

Below is a brief example of running the `k8s_scale_rapid.sh` test and generating a report from the results.

1. Run the test

    The test will run against the default `kubectl` configured cluster.
    ```sh
    $ ./scaling/k8s_scale.sh
    ```

    Results are stored in the `results` directory. The results will comprise of one `JSON` file for the test, and
    one `.tar.gz` file for each node found in the cluster.

    > **Note:** Only the `collectd` based tests generate `.tar.gz` files. All other tests only generate a single
    > `JSON` file for each run.

1. Move the results files

    In order to generate the report, the results files should be moved into an appropriately named sub-directory.
    The report generator can process and compare multiple sets of results. Each set of results should be placed
    into its own sub-directory. The below example uses the name `run1` as an example:

    ```sh
    $ cd results
    $ mkdir run1
    $ mv *.json run1
    $ mv *.tar.gz run1
    ```

    This sequence can be repeated to gather multiple test data sets. Place each data set in its own subdirectory.
    The report generator will process and compare all data set subdirectories found in the `results` directory.

1. Generate the report

    The report generator in the `report` subdirectory processes the sub-directories of the `results` directory
    to produce a `PDF` report and individual `PNG` based graphs.. The report generator utilises `docker` to create
    a docker image containing all the tooling necessary.

    ```sh
    $ cd report
    $ ./makereport.sh
    ...
    $ tree output
    output/
    ├── dut-1.png
    ├── metrics_report.pdf
    ├── scaling-1.png
    ├── scaling-2.png
    ├── scaling-3.png
    └── scaling-4.png
    ```
