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
| config | Configuration scripts |
| lib | General library helper functions for forming and launching workloads, and storing results in a uniform manner to aid later analysis |
| scaling | Tests to measure scaling, such as linear or parallel launching of pods |
| report | Rmarkdown based report generator, used to produce a PDF comparison report of 1 or more sets of results |


## Results storage and analysis

The tools generate JSON formatted results files via the `lib/json.bash` functions. The `metrics_json_save()`
function in that file has the ability to also `curl` or `socat` the JSON results to a database defined
by environment variables (see the file source for details). This method has been used to store results in
Elasticsearch and InfluxDB databases for instance, but should be adaptable to use with any REST API that accepts
JSON input.
