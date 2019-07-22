#!/bin/bash
# Copyright (c) 2019 Intel Corporation
# 
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Pull in some common, useful, items
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

input_yaml="bb.yaml.in"
generated_yaml="generated.yaml"
deployment="busybox"

stats_pod="stats"

export RUNTIME="kata-qemu"
NUM_PODS=${NUM_PODS:-20}
STEP=${STEP:-1}

LABEL=${LABEL:-magiclabel}
LABELVALUE=${LABELVALUE:-gandalf}

# sleep and timeout times for k8s actions, in seconds
wait_time=${wait_time:-30}
delete_wait_time=${delete_wait_time:-600}
settle_time=${settle_time:-5}
use_kata_runtime=${use_kata_runtime:-no}

# Set some default metrics env vars
TEST_ARGS="runtime=${RUNTIME}"
TEST_NAME="k8s scaling"

get_num_nodes() {
	n=$(kubectl get nodes --no-headers=true | wc -l)
	echo "$n"
}

# $1 is the launch time in seconds this pod/container took to start up.
# $2 is the number of pod/containers under test
grab_stats() {
	local launch_time=$1
	local n_pods=$2
	info "And grab some stats"
	# Tell mpstat to measure over a short period, not only so we get slightly de-noised data, but also
	# if you don't tell it the period, you will get the avg since boot, which is not what we want.
	local cpu_idle=$(kubectl exec -ti ${stats_pod} -- sh -c "mpstat -u 3 1 | tail -1 | awk '{print \$11}'" | sed 's/\r//')
	local mem_free=$(kubectl exec -ti ${stats_pod} -- sh -c "free | tail -2 | head -1 | awk '{print \$4}'" | sed 's/\r//')

	info "idle [$cpu_idle] free [$mem_free] launch [$launch_time]"

	# Annoyingly, it seems sometimes once in a while we don't get an answer!
	# We should really retry, but for now, make the json valid at least
	cpu_idle=${cpu_idle:-0}
	mem_free=${mem_free:-0}

	local json="$(cat << EOF
	{
		"n_pods": {
			"Result": ${n_pods},
			"Units" : "int"
		},
		"cpu_idle": {
			"Result": ${cpu_idle},
			"Units" : "%"
		},
		"launch_time": {
			"Result": $launch_time,
			"Units" : "s"
		},
		"mem_free": {
			"Result": ${mem_free},
			"Units" : "kb"
		}
	}
EOF
)"
	metrics_json_add_array_element "$json"
}

init() {
	info "Initialising"
	info "Checking k8s accessible"
	local worked=$( kubectl get nodes > /dev/null 2>&1 && echo $? || echo $? )
	if [ "$worked" != 0 ]; then
		die "kubectl failed to get nodes"
	fi

	info $(get_num_nodes) "k8s nodes found"
	# We could check we have just the one node here - right now this is a single node
	# test!! - because, our stats gathering is rudimentry, as k8s does not provide
	# a nice way to do it (unless you want to parse 'descibe nodes')
	# Have a read of https://github.com/kubernetes/kubernetes/issues/25353

	# FIXME - check the node(s) can run enough pods - check 'max-pods' in the
	# kubelet config - from 'kubectl describe node -o json' ?

	# Launch our stats gathering pod
	kubectl apply -f ${stats_pod}.yaml
	kubectl wait --for=condition=Ready pod "${stats_pod}"

	# FIXME - we should probably 'warm up' the cluster with the container image(s) we will
	# use for testing, otherwise the download time will likely be included in the first pod
	# boot time.

	# And now we can set up our results storage then...
	metrics_json_init "k8s"
	save_config
}

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"testname": "${TEST_NAME}",
		"NUM_PODS": "${NUM_PODS}",
		"STEP": "${STEP}",
		"wait_time": "${wait_time}",
		"delete_wait_time": "${delete_wait_time}",
		"settle_time": "${settle_time}"
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

	if [ "$use_kata_runtime" != "no" ]; then
		sed -e "s|@REPLICAS@|${reqs}|g" \
		    -e "s|@RUNTIMECLASS@|${RUNTIME}|g" \
		    -e "s|@DEPLOYMENT@|${deployment}|g" \
		    -e "s|@LABEL@|${LABEL}|g" \
		    -e "s|@LABELVALUE@|${LABELVALUE}|g" \
		    < ${input_yaml} > ${generated_yaml}
    else
        sed -e "s|@REPLICAS@|${reqs}|g" \
		    -e "/@RUNTIMECLASS@/d" \
		    -e "s|@DEPLOYMENT@|${deployment}|g" \
		    -e "s|@LABEL@|${LABEL}|g" \
		    -e "s|@LABELVALUE@|${LABELVALUE}|g" \
		    < ${input_yaml} > ${generated_yaml}
    fi

		info "Applying changes"
		# FIXME - time taken in 'seconds' - we can do better than that, if we
		# use the date nanosecond stamp, and steal the magic from the density test script.
        # switch to 'date +%N'
		local start_time=$(date +%s)
		kubectl apply -f ${generated_yaml}

		#cmd="kubectl get pods | grep busybox | grep Completed"
		kubectl rollout status --timeout=${wait_time}s deployment/${deployment}
		local end_time=$(date +%s)
		local total_seconds=$(( end_time - start_time ))
		info "Took $total_seconds ($end_time - $start_time)"
		sleep ${settle_time}
		grab_stats $total_seconds $reqs
	done
}

cleanup() {
	info "Cleaning up"

	# First try to save any results we got
	metrics_json_end_array "BootResults"

	kubectl delete pod --wait=true --timeout=${delete_wait_time}s "${stats_pod}" || true
	local start_time=$(date +%s)
	kubectl delete deployment --wait=true --timeout=${delete_wait_time}s "${deployment}" || true
	for x in $(seq 1 ${delete_wait_time}); do
		local npods=$(kubectl get pods -l=${LABEL}=${LABELVALUE} -o=name | wc -l)
		if [ $npods -eq 0 ]; then
			echo "All pods have terminated at cycle $x"
			local alldied=true
			break;
		fi
		sleep 1
	done
	local end_time=$(date +%s)
	local total_seconds=$(( end_time - start_time ))
	if [ -z "$alldied" ]; then
		echo "ERROR: Not all pods died!"
	fi
	info "Delete Took $total_seconds ($end_time - $start_time)"

	local json="$(cat << EOF
	"Delete": {
		"Result": ${total_seconds},
		"Units" : "s"
	}
EOF
)"

	metrics_json_add_fragment "$json"
	metrics_json_save
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
    echo -e "\tuse_kata_runtime (${use_kata_runtime})"
    echo -e "\t\tspecify yes or no to use kata runtime"
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

