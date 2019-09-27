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
