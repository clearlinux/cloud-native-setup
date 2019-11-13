#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Helper routines for setting up a constant CPU load on the cluster/nodes

CPULOAD_DIR=${THIS_FILE%/*}

# Default to testing all cores
SMF_CPU_LOAD_NODES_NCPU=${SMF_CPU_LOAD_NODES_NCPU:-0}
# Default to 100% load (yes, this might kill your node)
SMF_CPU_LOAD_NODES_PERCENT=${SMF_CPU_LOAD_NODES_PERCENT:-}
# Default to not setting any limits or requests, so no cpuset limiting and
# no cpu core pinning
SMF_CPU_LOAD_NODES_LIMIT=${SMF_CPU_LOAD_NODES_LIMIT:-}
SMF_CPU_LOAD_NODES_REQUEST=${SMF_CPU_LOAD_NODES_REQUEST:-}

cpu_load_post_deploy_sleep=${cpu_load_post_deploy_sleep:-30}

cpu_per_node_daemonset=cpu-load
clean_up_cpu_per_node=false

# Use a DaemonSet to place one cpu stressor on each node.
cpu_per_node_init() {
	info "Generating per-node CPU load daemonset"

	local ds_template=${CPULOAD_DIR}/cpu_load_daemonset.yaml.in
	local ds_yaml=${ds_template%\.in}

	# Grab a copy of the template
	cp -f ${ds_template} ${ds_yaml}

	# If a setting is not used (defined), then delete its relevant
	# lines from the YAML. Note, the YAML is constructed when necessary
	# with comments on the correct lines to ensure all necessary lines are
	# deleted
	if [ -z "$SMF_CPU_LOAD_NODES_NCPU" ]; then
		sed -i '/CPU_NCPU/d' ${ds_yaml}
	fi

	if [ -z "${SMF_CPU_LOAD_NODES_PERCENT}" ]; then
		sed -i '/CPU_PERCENT/d' ${ds_yaml}
	fi

	if [ -z "${SMF_CPU_LOAD_NODES_LIMIT}" ]; then
		sed -i '/CPU_LIMIT/d' ${ds_yaml}
	fi

	if [ -z "${SMF_CPU_LOAD_NODES_REQUEST}" ]; then
		sed -i '/CPU_REQUEST/d' ${ds_yaml}
	fi

	# And then finally replace all the remaining defined parts with the
	# real values.
	sed -i \
		-e "s|@CPU_NCPU@|${SMF_CPU_LOAD_NODES_NCPU}|g" \
		-e "s|@CPU_PERCENT@|${SMF_CPU_LOAD_NODES_PERCENT}|g" \
		-e "s|@CPU_LIMIT@|${SMF_CPU_LOAD_NODES_LIMIT}|g" \
		-e "s|@CPU_REQUEST@|${SMF_CPU_LOAD_NODES_REQUEST}|g" \
		${ds_yaml}

	# Launch the daemonset...
	info "Deploying cpu-load-per-node daemonset"
	kubectl apply -f ${ds_yaml}
	kubectl rollout status --timeout=${wait_time}s daemonset/${cpu_per_node_daemonset}
	clean_up_cpu_per_node=yes
	info "cpu-load-per-node daemonset Deployed"
	if [ -n "$cpu_load_post_deploy_sleep" ]; then
		info "Sleeping ${cpu_load_post_deploy_sleep}s for cpu-load to settle"
		sleep ${cpu_load_post_deploy_sleep}
	fi

	# And store off our config into the JSON results
	metrics_json_start_array
	local json="$(cat << EOF
	{
		"LOAD_NODES_NCPU": "${SMF_CPU_LOAD_NODES_NCPU}",
		"LOAD_NODES_PERCENT": "${SMF_CPU_LOAD_NODES_PERCENT}",
		"LOAD_NODES_LIMIT": "${SMF_CPU_LOAD_NODES_LIMIT}",
		"LOAD_NODES_REQUEST": "${SMF_CPU_LOAD_NODES_REQUEST}"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "cpu-load"
}

cpu_load_init() {
	info "Check if we need CPU load generators..."
	# This is defaulted of off (not defined), unless the high level test requests it.
	if [ -n "$SMF_CPU_LOAD_NODES" ]; then
		info "Initialising per-node CPU load"
		cpu_per_node_init
	fi
}

cpu_load_shutdown() {
	if [ "$clean_up_cpu_per_node" = "yes" ]; then
		info "Cleaning up cpu per node load daemonset"
		kubectl delete daemonset --wait=true --timeout=${delete_wait_time}s "${cpu_per_node_daemonset}" || true
	fi
}
