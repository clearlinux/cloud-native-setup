#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Pull in some common, useful, items
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"
source "${SCRIPT_PATH}/common.bash"
source "${SCRIPT_PATH}/../collectd/collectd.bash"

NUM_PODS=${NUM_PODS:-20}
STEP=${STEP:-1}

LABELVALUE=${LABELVALUE:-gandalf}

pod_command="[\"tail\", \"-f\", \"/dev/null\"]"

# Set some default metrics env vars
TEST_ARGS="runtime=${RUNTIME}"
TEST_NAME="k8s rapid"

# $1 is the launch time in seconds this pod/container took to start up.
# $2 is the number of pod/containers under test
grab_stats() {
	local launch_time_ms=$1
	local n_pods=$2
	local cpu_idle=()
	local mem_free=()
	local total_mem_used=0

	info "And grab some stats"

	local date_json="$(cat << EOF
			"date": {
				"ns": $(date +%s%N),
				"Date": "$(date -u +"%Y-%m-%dT%T.%3N")"
			}
EOF
	)"
	metrics_json_add_array_fragment "$date_json"

	local pods_json="$(cat << EOF
			"n_pods": {
				"Result": ${n_pods},
				"Units" : "int"
			}
EOF
	)"
	metrics_json_add_array_fragment "$pods_json"

	local launch_json="$(cat << EOF
			"launch_time": {
				"Result": $launch_time_ms,
				"Units" : "ms"
			}
EOF
	)"
	metrics_json_add_array_fragment "$launch_json"

	# start the node utilization array
	metrics_json_start_nested_array

	# TODO move tracking of noschedule tracking to collectd plugin or pull from system setup data
	# grab pods in the collectd daemonset
	# use 3 for the file descriptor rather than stdin otherwise the sh commands
	# in the middle will read the rest of stdin
	while read -u 3 name node; do
		# look for taint that prevents scheduling
		local noschedule=false
		local t_match_values=$(kubectl get node ${node} -o json | jq 'select(.spec.taints) | .spec.taints[].effect == "NoSchedule"')
		for v in $t_match_values; do
			if [[ $v == true ]]; then
				noschedule=true
				break
			fi
		done

		info "launch [$launch_time_ms]"

		local util_json="$(cat << EOF
		{
			"node": "${node}",
			"noschedule": "${noschedule}"
		}
EOF
		)"

		metrics_json_add_nested_array_element "$util_json"

	done 3< <(kubectl get pods --selector name=collectd-pods -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')

	metrics_json_end_nested_array "node_util"

	metrics_json_close_array_element
}

init() {
	info "Initialising"

	local cmds=("bc" "jq")
	check_cmds "${cmds[@]}"

	info "Checking k8s accessible"
	local worked=$( kubectl get nodes > /dev/null 2>&1 && echo $? || echo $? )
	if [ "$worked" != 0 ]; then
		die "kubectl failed to get nodes"
	fi

	info $(get_num_nodes) "k8s nodes in 'Ready' state found"

	k8s_api_init

	# Launch our stats gathering pod
	init_stats $wait_time

	# And now we can set up our results storage then...
	metrics_json_init "k8s"
	save_config
}

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"testname": "${TEST_NAME}",
		"NUM_PODS": ${NUM_PODS},
		"STEP": ${STEP},
		"wait_time": ${wait_time},
		"delete_wait_time": ${delete_wait_time},
		"settle_time": ${settle_time}
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Config"
}

run() {
	info "Running test"

	trap cleanup EXIT QUIT KILL

	metrics_json_start_array

	for reqs in $(seq ${STEP} ${STEP} ${NUM_PODS}); do
		info "Testing replicas ${reqs} of ${NUM_PODS}"
		# Generate the next yaml file

		local runtime_command
		if [ -n "$RUNTIME" ]; then
			runtime_command="s|@RUNTIMECLASS@|${RUNTIME}|g"
		else
			runtime_command="/@RUNTIMECLASS@/d"
		fi

		local input_template
		local generated_file
		if [ "$use_api" != "no" ]; then
			input_template=$input_json
			generated_file=$generated_json
		else
			input_template=$input_yaml
			generated_file=$generated_yaml
		fi

		sed -e "s|@REPLICAS@|${reqs}|g" \
			-e $runtime_command \
			-e "s|@DEPLOYMENT@|${deployment}|g" \
			-e "s|@LABEL@|${LABEL}|g" \
			-e "s|@LABELVALUE@|${LABELVALUE}|g" \
			-e "s|@GRACE@|${grace}|g" \
			-e "s#@PODCOMMAND@#${pod_command}#g" \
			< ${input_template} > ${generated_file}

		info "Applying changes"
		local start_time=$(date +%s%N)
		if [ "$use_api" != "no" ]; then
			# If this is the first launch of the deploy, we need to use a different URL form.
			if [ $reqs == ${STEP} ]; then
				curl -s ${API_ADDRESS}:${API_PORT}/apis/apps/v1/namespaces/default/deployments -XPOST -H 'Content-Type: application/json' -d@${generated_file} > /dev/null
			else
				curl -s ${API_ADDRESS}:${API_PORT}/apis/apps/v1/namespaces/default/deployments/${deployment} -XPATCH -H 'Content-Type:application/strategic-merge-patch+json' -d@${generated_file} > /dev/null
			fi
		else
			kubectl apply -f ${generated_file}
		fi

		kubectl rollout status --timeout=${wait_time}s deployment/${deployment}
		local end_time=$(date +%s%N)
		local total_milliseconds=$(( (end_time - start_time) / 1000000 ))
		info "Took $total_milliseconds ms ($end_time - $start_time)"

		sleep ${settle_time}
		grab_stats $total_milliseconds $reqs
	done
}

cleanup() {
	info "Cleaning up"

	# First try to save any results we got
	metrics_json_end_array "BootResults"

	local start_time=$(date +%s%N)
	kubectl delete deployment --wait=true --timeout=${delete_wait_time}s ${deployment} || true
	for x in $(seq 1 ${delete_wait_time}); do
		local npods=$(kubectl get pods -l=${LABEL}=${LABELVALUE} -o=name | wc -l)
		if [ $npods -eq 0 ]; then
			echo "All pods have terminated at cycle $x"
			local alldied=true
			break;
		fi
		sleep 1
	done
	local end_time=$(date +%s%N)
	local total_milliseconds=$(( (end_time - start_time) / 1000000 ))
	if [ -z "$alldied" ]; then
		echo "ERROR: Not all pods died!"
	fi
	info "Delete Took $total_milliseconds ms ($end_time - $start_time)"

	local json="$(cat << EOF
	"Delete": {
		"Result": ${total_milliseconds},
		"Units" : "ms"
	}
EOF
)"

	metrics_json_add_fragment "$json"
	metrics_json_save

	cleanup_stats $delete_wait_time

	k8s_api_shutdown
}

show_vars()
{
	echo -e "\nEnvironment variables:"
	echo -e "\tName (default)"
	echo -e "\t\tDescription"
	echo -e "\tTEST_NAME (${TEST_NAME})"
	echo -e "\t\tCan be set to over-ride the default JSON results filename"
	echo -e "\tNUM_PODS (${NUM_PODS})"
	echo -e "\t\tNumber of pods to launch"
	echo -e "\tSTEP (${STEP})"
	echo -e "\t\tNumber of pods to launch per cycle"
	echo -e "\twait_time (${wait_time})"
	echo -e "\t\tSeconds to wait for pods to become ready"
	echo -e "\tdelete_wait_time (${delete_wait_time})"
	echo -e "\t\tSeconds to wait for all pods to be deleted"
	echo -e "\tsettle_time (${settle_time})"
	echo -e "\t\tSeconds to wait after pods ready before taking measurements"
	echo -e "\tuse_api (${use_api})"
	echo -e "\t\tspecify yes or no to use the API to launch pods"
	echo -e "\tgrace (${grace})"
	echo -e "\t\tspecify the grace period in seconds for workload pod termination"
}

help()
{
	usage=$(cat << EOF
Usage: $0 [-h] [options]
   Description:
	Launch a series of workloads and take memory metric measurements after
	each launch.
   Options:
		-h,    Help page.
EOF
)
	echo "$usage"
	show_vars
}

main() {

	local OPTIND
	while getopts "h" opt;do
		case ${opt} in
		h)
			help
			exit 0;
			;;
		esac
	done
	shift $((OPTIND-1))
	init
	run
	# cleanup will happen at exit due to the shell 'trap' we registered
	# cleanup
}

main "$@"
