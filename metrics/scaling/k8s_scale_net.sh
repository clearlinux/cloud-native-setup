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

LABELVALUE=${LABELVALUE:-scale_net}

# Set some default metrics env vars
TEST_ARGS="runtime=${RUNTIME}"
TEST_NAME="k8s scaling net"
input_yaml="${SCRIPT_PATH}/net-serve.yaml.in"
input_json="${SCRIPT_PATH}/net-serve.json.in"
name_base_depl="net-serve"

# $1 is the launch time in seconds this pod/container took to start up.
# $2 is the number of pod/containers under test
# $3 is the time to pod network measure
grab_stats(){
    local launch_time_ms=$1
    local n_pods=$2
    local net_time=$3

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

    local time_to_pod_net_json="$(cat << EOF
                        "time_to_pod_net": {
                                "Result": ${net_time},
                                "Units" : "ms"
                            }
EOF
)"
    metrics_json_add_array_fragment "$time_to_pod_net_json"

    local launch_json="$(cat << EOF
                        "launch_time": {
                                "Result": $launch_time_ms,
                                "Units" : "ms"
                            }
EOF
)"
    metrics_json_add_array_fragment "$launch_json"

    info "launch [$launch_time_ms]"

    metrics_json_close_array_element
}

init() {
    info "Initialising"

    local cmds=("bc" "jq")
    check_cmds "${cmds[@]}"

    info "Checking Kubernetes accessible"
    local worked=$( kubectl get nodes > /dev/null 2>&1 && echo $? || echo $? )
    if [ "$worked" != 0 ]; then
        die "kubectl failed to get nodes"
    fi

    info $(get_num_nodes) "Kubernetes nodes in 'Ready' state found"

    framework_init
}

save_config() {
    metrics_json_start_array

    local json="$(cat << EOF
    {
        "testname": "${TEST_NAME}",
        "NUM_DEPLOYMENTS": ${NUM_DEPLOYMENTS},
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
	local header_post="Content-Type: application/json"
	local base_curl=${API_ADDRESS}:${API_PORT}/apis/apps/v1/namespaces/default/deployments

	trap cleanup EXIT QUIT KILL

	metrics_json_start_array

	for reqs in $(seq ${STEP} ${STEP} ${NUM_DEPLOYMENTS}); do
		local deployment="${name_base_depl}${reqs}"
		info "Testing replicas ${reqs} of ${NUM_DEPLOYMENTS}"
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

		sed -e $runtime_command \
			-e "s|@DEPLOYMENT@|${deployment}|g" \
			-e "s|@LABEL@|${LABEL}|g" \
			-e "s|@LABELVALUE@|${LABELVALUE}|g" \
			-e "s|@GRACE@|${grace}|g" \
			< ${input_template} > ${generated_file}

		info "Applying changes"
		local start_time=$(date +%s%N)

		if [ "$use_api" != "no" ]; then
			curl -s ${base_curl} -XPOST -H "${header_post}" -d@${generated_file} > /dev/null
		else
			kubectl apply -f ${generated_file}
		fi

		kubectl rollout status --timeout=${wait_time}s deployment/${deployment}
		kubectl expose --port=8080 deployment $deployment

        # Check service exposed
        cmd="kubectl get services $deployment -n default --no-headers=true"
        waitForProcess "$proc_wait_time" "$proc_sleep_time" "$cmd" "Waiting for service"

		IP=$(kubectl get services $deployment -n default --no-headers=true | awk '{printf $3}')
		end_net=$(date +%s%N)
		info "IP: $IP"

		# service health check
        cmd="curl --noproxy \"*\" http://$IP:8080/healthz --connect-timeout 1"
        waitForProcess "$proc_wait_time" "$proc_sleep_time" "$cmd" "http server is not ready yet!!"

		RESP=$(curl -s --noproxy "*" http://$IP:8080/echo?msg=curl%20request%20to%20$deployment)
		local end_time=$(date +%s%N)
		info "http reply: $RESP"

		local total_milliseconds=$(( (end_time - start_time) / 1000000 ))
		local net_diff=$(( (end_net - start_time) / 1000000 ))
		info "Took $total_milliseconds ms ($end_time - $start_time)"
		info "Net took $net_diff ms"

		kubectl delete service $deployment
		if [ $? -ne 0 ]; then
			echo "kubectl delete service failed"
			exit
		fi

		sleep ${settle_time}
		grab_stats $total_milliseconds $reqs $net_diff
	done
}

cleanup() {
    info "Cleaning up"

    # First try to save any results we got
    metrics_json_end_array "BootResults"

    local start_time=$(date +%s%N)

    for reqs in $(seq ${STEP} ${STEP} ${NUM_DEPLOYMENTS}); do
        local deployment="${name_base_depl}${reqs}"
        kubectl delete deployment --wait=true --timeout=${delete_wait_time}s ${deployment} || true
    done

    for x in $(seq 1 ${delete_wait_time}); do
        local npods=$(kubectl get pods -l=${LABEL}=${LABELVALUE} -o=name | wc -l)
        if [ $npods -eq 0 ]; then
            echo "All pods have terminated at cycle $x"
            local alldied=true
            break;
        fi
        sleep 1
    done

    if [ -z "$alldied" ]; then
        echo "ERROR: Not all pods died!"
    fi

    local end_time=$(date +%s%N)
    local total_milliseconds=$(( (end_time - start_time) / 1000000 ))
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

show_vars() {
	echo -e "\nEnvironment variables:"
	echo -e "\tName (default)"
	echo -e "\t\tDescription"
	echo -e "\tNUM_DEPLOYMENTS (${NUM_DEPLOYMENTS})"
	echo -e "\t\tNumber of deployments to launch"
	echo -e "\tSTEP (${STEP})"
	echo -e "\t\tNumber of pods to launch per cycle"
	echo -e "\twait_time (${wait_time})"
	echo -e "\t\tSeconds to wait for pods to become ready"
	echo -e "\tproc_wait_time (${proc_wait_time})"
	echo -e "\t\tSeconds to wait for net server process to become ready"
	echo -e "\tdelete_wait_time (${delete_wait_time})"
	echo -e "\t\tSeconds to wait for all pods to be deleted"
	echo -e "\tsettle_time (${settle_time})"
	echo -e "\t\tSeconds to wait after pods ready before taking measurements"
	echo -e "\tuse_api (${use_api})"
	echo -e "\t\tspecify yes or no to use the API to launch pods"
	echo -e "\tgrace (${grace})"
	echo -e "\t\tspecify the grace period in seconds for workload pod termination"
}

help() {
    usage=$(cat << EOF
    Usage: $0 [-h] [options]
    Description:
        Launch a series of workloads and take time to pod network  metric measurements after
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
}

main "$@"
