#!/bin/bash
#
# Copyright (c) 2017,2018,2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

THIS_FILE=$(readlink -f ${BASH_SOURCE[0]})
LIB_DIR=${THIS_FILE%/*}
RESULT_DIR="${LIB_DIR}/../results"

source ${LIB_DIR}/json.bash
source ${LIB_DIR}/k8s-api.bash
source ${LIB_DIR}/cpu-load.bash
source ${LIB_DIR}/mem-load.bash
source /etc/os-release || source /usr/lib/os-release

die() {
	local msg="$*"
	echo "ERROR: $msg" >&2
	exit 1
}

warn() {
	local msg="$*"
	echo "WARNING: $msg"
}

info() {
	local msg="$*"
	echo "INFO: $msg"
}

# This function checks existence of commands.
# They can be received standalone or as an array, e.g.
#
# cmds=(“cmd1” “cmd2”)
# check_cmds "${cmds[@]}"
check_cmds()
{
	local cmd req_cmds=( "$@" )
	for cmd in "${req_cmds[@]}"; do
		if ! command -v "$cmd" > /dev/null 2>&1; then
			die "command $cmd not available"
		fi
		echo "command: $cmd: yes"
	done
}

# Print a banner to the logs noting clearly which test
# we are about to run
test_banner()
{
	echo -e "\n===== starting test [$1] ====="
}

# Initialization/verification environment. This function makes
# minimal steps for metrics/tests execution.
init_env()
{
	test_banner "${TEST_NAME}"

	cmd=("kubectl")

	# check dependencies
	check_cmds "${cmd[@]}"

	# We could try to clean the k8s cluster here... but that
	# might remove some pre-installed soak tests etc. that have
	# been deliberately injected into the cluster under test.
}

framework_init() {
	info "Initialising"

	check_cmds "${cmds[@]}"

	info "Checking k8s accessible"
	local worked=$( kubectl get nodes > /dev/null 2>&1 && echo $? || echo $? )
	if [ "$worked" != 0 ]; then
		die "kubectl failed to get nodes"
	fi

	info $(get_num_nodes) "k8s nodes in 'Ready' state found"

	k8s_api_init

	# Launch our stats gathering pod
	if [ -n "$SMF_USE_COLLECTD" ]; then
		info "Setting up collectd"
		init_stats $wait_time
	fi

	# And now we can set up our results storage then...
	metrics_json_init "k8s"
	save_config

	# Initialise load generators now - after json init, as they may
	# produce some json results (config) data.
	cpu_load_init
	mem_load_init

}

framework_shutdown() {
	metrics_json_save
	k8s_api_shutdown
	cpu_load_shutdown
	mem_load_shutdown

	if [ -n "$SMF_USE_COLLECTD" ]; then
		cleanup_stats
	fi

}

# finds elements in $1 that are not in $2
find_unique_pods() {
	local list_a=$1
	local list_b=$2

	new_pods=()
	for a in $list_a; do
			local in_b=false
				for b in $list_b; do
					if [[ $a == $b ]]; then
							in_b=true
								break
						fi
				done
				if [[ $in_b == false ]]; then
					new_pods[${#new_pods[@]}]=$a
				fi
		done
}

# waits for process to complete within a given time range
waitForProcess(){
    wait_time="$1"
    sleep_time="$2"
    cmd="$3"
    proc_info_msg="$4"

    while [ "$wait_time" -gt 0 ]; do
        if eval "$cmd"; then
            return 0
        else
            info "$proc_info_msg"
            sleep "$sleep_time"
            wait_time=$((wait_time-sleep_time))
        fi
    done
    return 1
}
