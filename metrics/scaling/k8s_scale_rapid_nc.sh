#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Pull in some common, useful, items
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
LABELVALUE=${LABELVALUE:-rapid_nc}
source "${SCRIPT_PATH}/../lib/common.bash"
source "${SCRIPT_PATH}/common.bash"
source "${SCRIPT_PATH}/../collectd/collectd.bash"

SMF_USE_COLLECTD=true

# Network latency test parameters:
# number of requests to be sent after each scaling step
nc_reqs=${nc_reqs:-1000}
# length of each request [bytes]
nc_req_msg_len=${nc_req_msg_len:-1000}
# port that request servers listen to in pods
nc_port=33101
# request message
nc_req_msg=$(head -c $nc_req_msg_len /dev/zero | tr  '\0' 'x')
nc_percentiles=(0 1 5 25 50 75 95 99 100)

pod_command="[\"nc\", \"-lk\", \"-p\", \"${nc_port}\", \"-e\", \"/bin/sh\", \"-c\", \"/bin/echo \${EPOCHREALTIME/./}; /bin/cat; /bin/echo \${EPOCHREALTIME/./}\"]"

# Set some default metrics env vars
TEST_ARGS="runtime=${RUNTIME}"
TEST_NAME="k8s rapid nc"

# $1 is the launch time in seconds this pod/container took to start up.
# $2 is the number of pod/containers under test
grab_stats() {
	local launch_time_ms=$1
	local n_pods=$2
	shift ; shift
	local latency_percentiles=($@) # array of percentiles
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

	local latency_json="$(cat << EOF
			"latency_time": {
				"Percentiles": [$(IFS=, ; echo "${latency_percentiles[*]}")],
				"Result": ${latency_percentiles[$(( ${#latency_percentiles[@]} / 2 ))]},
				"Units" : "ms"
			}
EOF
	)"

	metrics_json_add_array_fragment "$latency_json"

	info "launch [$launch_time_ms]"

	metrics_json_close_array_element
}

init() {
	framework_init
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
		"settle_time": ${settle_time},
		"nc_reqs": ${nc_reqs},
		"nc_req_msg_len": ${nc_req_msg_len},
		"nc_percentiles": [$(IFS=, ; echo "${nc_percentiles[*]}")]
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

		# Measure network latency
		if [[ ${nc_reqs} -ge 1 ]]; then
			mkdir -p "$RESULT_DIR" 2>/dev/null || true
			local latency_raw_output="$RESULT_DIR/${TEST_NAME// /-}.tmaster_tworker_pods_req_ipaddr_lattot_latconn_latio_latdisconn_rx.raw"
			local pod_ips=($(kubectl get pods --selector ${LABEL}=${LABELVALUE} -o json | jq -r '.items[].status.podIP'))
			local pod_ips_len=${#pod_ips[@]}
			if [[ ${reqs} != ${pod_ips_len} ]]; then
				info "WARNING: pod IP count mismatch expected ${reqs} found ${pod_ips_len}"
			fi
			info "Measuring latency, sending ${nc_reqs} messages to ${reqs} pods (~$((nc_reqs / reqs)) messages each)"
			local latency_failures=0
			local latency_pod_array=()

			# send $nc_reqs messages, go through pods
			local req_index=0
			local pod_index=0
			while [[ $req_index -lt $nc_reqs ]] && [[ $pod_ips_len -gt 0 ]]; do
				req_index=$(( req_index + 1 ))
				pod_index=$(( pod_index + 1 ))
				if [[ $pod_index -ge $pod_ips_len ]]; then
					pod_index=0
				fi
				local pod_ip=${pod_ips[$pod_index]}
				local latency_failed=0
				local latency_pod_start_time=${EPOCHREALTIME/./}
				local latency_pod_start_response_end=$(echo ${latency_pod_start_time} ${nc_req_msg} | nc ${pod_ip} ${nc_port})
				# start_response_end contents: <worker_start_ts> <master_ts> <nc_req_msg> <worker_end_ts>
				local latency_pod_end_time=${EPOCHREALTIME/./}
				local latency_response_microseconds=$(( latency_pod_end_time - latency_pod_start_time ))
				local latency_pod_response=$(echo $latency_pod_start_response_end | awk '{print $3}')
				if [[ "$latency_pod_response" != "${nc_req_msg}" ]]; then
					latency_failures=$(( latency_failures + 1 ))
					local latency_pod_first_t=$latency_pod_end_time
					local latency_pod_last_t=$latency_pod_end_time
					latency_failed=1
				else
					local latency_pod_first_t=$(echo $latency_pod_start_response_end | awk '{print $1}')
					local latency_pod_last_t=$(echo $latency_pod_start_response_end | awk '{print $4}')
				fi
				local latency_pod_local_io=$(( latency_pod_last_t - latency_pod_first_t ))
				local latency_pod_conn=$(( latency_pod_first_t - latency_pod_start_time ))
				local latency_pod_disconn=$(( latency_pod_end_time - latency_pod_last_t ))
				latency_pod_array+=($latency_response_microseconds)
				echo "$latency_pod_start_time $latency_pod_first_t $reqs $req_index $pod_ip $latency_response_microseconds $latency_pod_conn $latency_pod_local_io $latency_pod_disconn $(echo $latency_pod_start_response_end | wc -c)" >> $latency_raw_output
			done
			IFS=$'\n'
			local latency_pod_array_sorted=($(sort -n <<<"${latency_pod_array[*]}"))
			unset IFS
			local latency_pod_array_len=${#latency_pod_array[@]}
			local latency_percentiles=()
			for p in ${nc_percentiles[@]}; do
				if [[ $p -lt 100 ]]; then
					latency_percentiles+=(${latency_pod_array_sorted[$(bc <<<"$latency_pod_array_len * $p / 100")]})
				else
					# Asking for a value that is greater than 100 % of measured values.
					# This is the way to save the maximum value.
					latency_percentiles+=(${latency_pod_array_sorted[$(bc <<<"$latency_pod_array_len - 1")]})
				fi
			done
			info "Latency percentiles [ms] ${nc_percentiles[@]} %: ${latency_percentiles[@]}"
		else
			local latency_avg_ms=0
			local latency_percentiles=()
			for p in ${nc_percentiles[@]}; do
				latency_percentiles+=(0)
			done
		fi

		grab_stats $total_milliseconds $reqs ${latency_percentiles[@]}
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
