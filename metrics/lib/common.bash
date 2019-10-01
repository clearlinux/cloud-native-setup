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

# Debugging: run "nc -k -l -p 33720" and add breakpoints in scripts:
# BP="my-breakpoint-1" eval $BP_CALLHOME
BP_HOME=127.0.0.1 BP_PORT=33720
BP_CALLHOME='BP_FIFO=/tmp/$BP_HOME.$BP_PORT.$BP; (rm -f $BP_FIFO; mkfifo $BP_FIFO) && (echo "\"c\" continues"; echo -n "($BP) "; tail -f $BP_FIFO) | nc $BP_HOME $BP_PORT | while read cmd; do if test "$cmd" = "c" ; then echo -n "" >$BP_FIFO; sleep 0.1; fuser -k $BP_FIFO >/dev/null 2>&1; break; else eval $cmd >$BP_FIFO 2>&1; echo -n "($BP) "  >$BP_FIFO; fi; done'

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

