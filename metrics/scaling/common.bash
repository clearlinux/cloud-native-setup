#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

input_yaml="${SCRIPT_PATH}/bb.yaml.in"
input_json="${SCRIPT_PATH}/bb.json.in"
generated_yaml="${SCRIPT_PATH}/generated.yaml"
generated_json="${SCRIPT_PATH}/generated.json"
deployment="busybox"

stats_pod="stats"

NUM_PODS=${NUM_PODS:-20}
NUM_DEPLOYMENTS=${NUM_DEPLOYMENTS:-20}
STEP=${STEP:-1}

LABEL=${LABEL:-magiclabel}
LABELVALUE=${LABELVALUE:-scaling_common}

# sleep and timeout times for k8s actions, in seconds
wait_time=${wait_time:-30}
delete_wait_time=${delete_wait_time:-600}
settle_time=${settle_time:-5}
use_api=${use_api:-yes}
grace=${grace:-30}
proc_wait_time=${proc_wait_time:-20}
proc_sleep_time=2

declare -a new_pods
declare -A node_basemem
declare -A node_baseinode
