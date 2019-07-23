#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Run a set of the metrics tests to gather data to be used with the report
# generator. The general ideal is to have the tests configured to generate
# useful, meaninful and repeatable (stable, with minimised variance) results.
# If the tests have to be run more or longer to achieve that, then generally
# that is fine - this test is not intended to be quick, it is intended to
# be repeatable.

# Note - no 'set -e' in this file - if one of the metrics tests fails
# then we wish to continue to try the rest.
# Finally at the end, in some situations, we explicitly exit with a
# failure code if necessary.

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/../lib/common.bash"
RESULTS_DIR=${SCRIPT_DIR}/../results

# By default we run all the tests
RUN_ALL=1

help() {
	usage=$(cat << EOF
Usage: $0 [-h] [options]
   Description:
        This script gathers a number of metrics for use in the
        report generation script. Which tests are run can be
        configured on the commandline. Specifically enabling
        individual tests will disable the 'all' option, unless
        'all' is also specified last.
   Options:
        -a,         Run all tests (default).
        -h,         Print this help.
        -s,         Run the scaling tests.
EOF
)
	echo "$usage"
}

# Set up the initial state
init() {
	metrics_onetime_init

	local OPTIND
	while getopts "ahs" opt;do
		case ${opt} in
		a)
		    RUN_ALL=1
		    ;;
		h)
		    help
		    exit 0;
		    ;;
		s)
		    RUN_SCALING=1
		    RUN_ALL=
		    ;;
		?)
		    # parse failure
		    help
		    die "Failed to parse arguments"
		    ;;
		esac
	done
	shift $((OPTIND-1))
}

run_scaling() {
	echo "Running scaling tests"

	(cd scaling; ./k8s_scale.sh)
}

# Execute metrics scripts
run() {
	pushd "$SCRIPT_DIR/.."

	if [ -n "$RUN_ALL" ] || [ -n "$RUN_SCALING" ]; then
		run_scaling
	fi

	popd
}

finish() {
	echo "Now please create a suitably descriptively named subdirectory in"
	echo "$RESULTS_DIR and copy the .json results files into it before running"
	echo "this script again."
}

init "$@"
run
finish

