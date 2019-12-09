#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Helper routines for setting up a constant MEM load on the cluster/nodes

MEMLOAD_DIR=${THIS_FILE%/*}

# Default load: 50% of free memory per worker, run 1 worker
SMF_MEM_LOAD_WORKER_BYTES=${SMF_MEM_LOAD_WORKER_BYTES:-80%}
SMF_MEM_LOAD_MASTER_BYTES=${SMF_MEM_LOAD_MASTER_BYTES:-80%}
SMF_MEM_LOAD_WORKER_VMS=${SMF_MEM_LOAD_WORKER_VMS:-1}
SMF_MEM_LOAD_MASTER_VMS=${SMF_MEM_LOAD_MASTER_VMS:-1}
# Default memory limits or requests: none
SMF_MEM_LOAD_WORKER_LIMIT=${SMF_MEM_LOAD_WORKER_LIMIT:-}
SMF_MEM_LOAD_MASTER_LIMIT=${SMF_MEM_LOAD_MASTER_LIMIT:-}
SMF_MEM_LOAD_WORKER_REQUEST=${SMF_MEM_LOAD_WORKER_REQUEST:-}
SMF_MEM_LOAD_MASTER_REQUEST=${SMF_MEM_LOAD_MASTER_REQUEST:-}

mem_load_post_deploy_sleep=${mem_load_post_deploy_sleep:-30}

mem_load_worker_daemonset=mem-load-worker
mem_load_master_daemonset=mem-load-master
clean_up_mem_worker=false
clean_up_mem_master=false

# Use a DaemonSet to place one mem stressor on each node.
mem_per_node_init() {
	info "Generating per-node MEM load daemonset"

	local ds_template=${MEMLOAD_DIR}/mem_load_daemonset.yaml.in
	local ds_yaml_w=${ds_template%\.yaml.in}_worker.yaml
	local ds_yaml_m=${ds_template%\.yaml.in}_master.yaml

	# Grab a copy of the template
	cp -f ${ds_template} ${ds_yaml_w}
	cp -f ${ds_template} ${ds_yaml_m}

	# If a setting is not used (defined), then delete its relevant
	# lines from the YAML. Note, the YAML is constructed when necessary
	# with comments on the correct lines to ensure all necessary lines are
	# deleted
	if [ -z "${SMF_MEM_LOAD_WORKER_LIMIT}" ]; then
		sed -i '/MEM_LIMIT/d' ${ds_yaml_w}
	fi
	if [ -z "${SMF_MEM_LOAD_MASTER_LIMIT}" ]; then
		sed -i '/MEM_LIMIT/d' ${ds_yaml_m}
	fi

	if [ -z "${SMF_MEM_LOAD_WORKER_REQUEST}" ]; then
		sed -i '/MEM_REQUEST/d' ${ds_yaml_w}
	fi
	if [ -z "${SMF_MEM_LOAD_MASTER_REQUEST}" ]; then
		sed -i '/MEM_REQUEST/d' ${ds_yaml_m}
	fi

	# And then finally replace all the remaining defined parts with the
	# real values.
	sed -i \
	    -e "s|@MEM_NODE_ROLE@|worker|g" \
	    -e "s|@MEM_MATCH_ROLE_MASTER@|DoesNotExist|g" \
	    -e "s|@MEM_BYTES@|${SMF_MEM_LOAD_WORKER_BYTES}|g" \
	    -e "s|@MEM_WORKERS@|${SMF_MEM_LOAD_WORKER_VMS}|g" \
	    -e "s|@MEM_LIMIT@|${SMF_MEM_LOAD_WORKER_LIMIT}|g" \
	    -e "s|@MEM_REQUEST@|${SMF_MEM_LOAD_WORKER_REQUEST}|g" \
	    ${ds_yaml_w}
	sed -i \
	    -e "s|@MEM_NODE_ROLE@|master|g" \
	    -e "s|@MEM_MATCH_ROLE_MASTER@|Exists|g" \
	    -e "s|@MEM_BYTES@|${SMF_MEM_LOAD_MASTER_BYTES}|g" \
	    -e "s|@MEM_WORKERS@|${SMF_MEM_LOAD_MASTER_VMS}|g" \
	    -e "s|@MEM_LIMIT@|${SMF_MEM_LOAD_MASTER_LIMIT}|g" \
	    -e "s|@MEM_REQUEST@|${SMF_MEM_LOAD_MASTER_REQUEST}|g" \
	    ${ds_yaml_m}

	# Launch the daemonset...
	if [ -n "$SMF_MEM_LOAD_WORKER" ]; then
		info "Deploying ${mem_load_worker_daemonset} daemonset"
		kubectl apply -f ${ds_yaml_w}
		kubectl rollout status --timeout=${wait_time}s daemonset/${mem_load_worker_daemonset}
		clean_up_mem_worker=yes
		info "${mem_load_worker_daemonset} Deployed"
	fi
	if [ -n "$SMF_MEM_LOAD_MASTER" ]; then
		info "Deploying ${mem_load_master_daemonset} daemonset"
		kubectl apply -f ${ds_yaml_m}
		kubectl rollout status --timeout=${wait_time}s daemonset/${mem_load_master_daemonset}
		clean_up_mem_master=yes
		info "${mem_load_master_daemonset} Deployed"
	fi
	if [ -n "$mem_load_post_deploy_sleep" ]; then
		info "Sleeping ${mem_load_post_deploy_sleep}s for mem-load to settle"
		sleep ${mem_load_post_deploy_sleep}
	fi

	# And store off our config into the JSON results
	metrics_json_start_array
	local json="$(cat << EOF
	{
		"LOAD_WORKER": "${SMF_MEM_LOAD_WORKER}",
		"LOAD_WORKER_BYTES": "${SMF_MEM_LOAD_WORKER_BYTES}",
		"LOAD_WORKER_VMS": "${SMF_MEM_LOAD_WORKER_VMS}",
		"LOAD_WORKER_LIMIT": "${SMF_MEM_LOAD_WORKER_LIMIT}",
		"LOAD_WORKER_REQUEST": "${SMF_MEM_LOAD_WORKER_REQUEST}"
		"LOAD_MASTER": "${SMF_MEM_LOAD_MASTER}",
		"LOAD_MASTER_BYTES": "${SMF_MEM_LOAD_MASTER_BYTES}",
		"LOAD_MASTER_VMS": "${SMF_MEM_LOAD_MASTER_VMS}",
		"LOAD_MASTER_LIMIT": "${SMF_MEM_LOAD_MASTER_LIMIT}",
		"LOAD_MASTER_REQUEST": "${SMF_MEM_LOAD_MASTER_REQUEST}"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "mem-load"
}

mem_load_init() {
	info "Check if we need MEM load generators..."
	# This is defaulted of off (not defined), unless the high level test requests it.
	if [ -n "$SMF_MEM_LOAD_WORKER" ] || [ -n "$SMF_MEM_LOAD_MASTER" ]; then
		info "Initialising per-node MEM load"
		mem_per_node_init
	fi
}

mem_load_shutdown() {
	if [ "$clean_up_mem_worker" = "yes" ]; then
		info "Cleaning up ${mem_load_worker_daemonset} daemonset"
		kubectl delete daemonset --wait=true --timeout=${delete_wait_time}s "${mem_load_worker_daemonset}" || true
	fi
	if [ "$clean_up_mem_master" = "yes" ]; then
		info "Cleaning up ${mem_load_master_daemonset} daemonset"
		kubectl delete daemonset --wait=true --timeout=${delete_wait_time}s "${mem_load_master_daemonset}" || true
	fi
}
