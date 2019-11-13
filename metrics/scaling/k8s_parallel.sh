#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Measure pod create and delete times whilst launching
# them in parallel - try to measure any effects parallel pod
# launching has.

set -e

# Pull in some common, useful, items
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"
source "${SCRIPT_PATH}/common.bash"

LABELVALUE=${LABELVALUE:-parallel}

pod_command="[\"tail\", \"-f\", \"/dev/null\"]"

# Set some default metrics env vars
TEST_ARGS="runtime=${RUNTIME}"
TEST_NAME="k8s parallel"

# Kill off a deployment, and wait for it to finish dying off.
# $1 name of deployment
# $2 name of label to watch
# $3 value of label to watch
# $4 timeout to wait, in seconds
kill_deployment() {
	kubectl delete deployment --wait=true --timeout=${4}s "${1}" || true
	for x in $(seq 1 ${delete_wait_time}); do
		# FIXME
		local npods=$(kubectl get pods -l=${2}=${3} -o=name | wc -l)
		if [ $npods -eq 0 ]; then
			info "deployment has terminated"
			local alldied=true
			break;
		fi
		sleep 1
	done

	if [ -z "$alldied" ]; then
		info "Not all pods died"
	fi
}

# Run up a single pod, and kill it off. This will pre-warm any one-time/first-time
# elements, such as pulling down the container image if necessary.
warmup() {
	info "Warming up"

	trap cleanup EXIT QUIT KILL

	local runtime_command
	if [ -n "$RUNTIME" ]; then
			runtime_command="s|@RUNTIMECLASS@|${RUNTIME}|g"
	else
			runtime_command="/@RUNTIMECLASS@/d"
	fi

	# Always use the convenience of kubectl (not the REST API) to
	# run the warmup pod, why not.
	sed -e "s|@REPLICAS@|${reqs}|g" \
		-e $runtime_command \
		-e "s|@DEPLOYMENT@|${deployment}|g" \
		-e "s|@LABEL@|${LABEL}|g" \
		-e "s|@LABELVALUE@|${LABELVALUE}|g" \
		-e "s|@GRACE@|${grace}|g" \
		-e "s#@PODCOMMAND@#${pod_command}#g" \
		< ${input_yaml} > ${generated_yaml}

	info "Applying warmup pod"
	kubectl apply -f ${generated_yaml}
	info "Waiting for warmup"
	kubectl rollout status --timeout=${wait_time}s deployment/${deployment}

	info "Killing warmup pod"
	kill_deployment "${deployment}" "${LABEL}" "${LABELVALUE}" ${delete_wait_time}

}

# $1 is the launch time in seconds this pod/container took to start up.
# $2 is the delete time in seconds this pod/container took to start up.
# $2 is the number of pod/containers under test
save_stats() {
	local launch_time_ms=$1
	local delete_time_ms=$2
	local n_pods=$3

	local json="$(cat << EOF
	{
		"date": {
			"ns": $(date +%s%N),
			"Date": "$(date -u +"%Y-%m-%dT%T.%3N")"
		},
		"n_pods": {
			"Result": ${n_pods},
			"Units" : "int"
		},
		"launch_time": {
			"Result": $launch_time_ms,
			"Units" : "ms"
		},
		"delete_time": {
			"Result": $delete_time_ms,
			"Units" : "ms"
		}
	}
EOF
)"
	metrics_json_add_array_element "$json"
}

init() {
	info "Initialising"
	info "Checking Kubernetes accessible"
	local worked=$( kubectl get nodes > /dev/null 2>&1 && echo $? || echo $? )
	if [ "$worked" != 0 ]; then
		die "kubectl failed to get nodes"
	fi

	info $(get_num_nodes) "Kubernetes nodes found"
	# We could check we have just the one node here - right now this is a single node
	# test!! - because, our stats gathering is rudimentry, as k8s does not provide
	# a nice way to do it (unless you want to parse 'descibe nodes')
	# Have a read of https://github.com/kubernetes/kubernetes/issues/25353

	framework_init

	# Ensure we pre-cache the container image etc.
	warmup
}

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"testname": "${TEST_NAME}",
		"NUM_PODS": ${NUM_PODS},
		"STEP": ${STEP},
		"wait_time": ${wait_time},
		"delete_wait_time": ${delete_wait_time}
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
		info "Testing parallel replicas ${reqs} of ${NUM_PODS}"
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
			curl -s ${API_ADDRESS}:${API_PORT}/apis/apps/v1/namespaces/default/deployments -XPOST -H 'Content-Type: application/json' -d@${generated_file} > /dev/null
		else
			kubectl apply -f ${generated_file}
		fi

		kubectl rollout status --timeout=${wait_time}s deployment/${deployment}
		local end_time=$(date +%s%N)
		local total_milliseconds=$(( (end_time - start_time) / 1000000 ))
		info "Took $total_milliseconds ms ($end_time - $start_time)"

		# And now remove that deployment, ready to launch the next one
		local delete_start_time=$(date +%s%N)
		kill_deployment "${deployment}" "${LABEL}" "${LABELVALUE}" ${delete_wait_time}
		local delete_end_time=$(date +%s%N)
		local delete_total_milliseconds=$(( (delete_end_time - delete_start_time) / 1000000 ))
		info "Delete took $delete_total_milliseconds ms ($delete_end_time - $delete_start_time)"
		save_stats $total_milliseconds $delete_total_milliseconds $reqs
	done
}

cleanup() {
	info "Cleaning up"

	# First try to save any results we got
	metrics_json_end_array "BootResults"
	kill_deployment "${deployment}" "${LABEL}" "${LABELVALUE}" ${delete_wait_time}
	framework_shutdown
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
	Launch a series of workloads in a parallel manner and take memory metric measurements
	after each launch.
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
