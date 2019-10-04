#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Helper routines for generating JSON formatted results.

declare -a json_result_array
declare -a json_array_array
declare -a json_nested_array

# Default to dropping the data - in the very rare case that we
# call 'save' before we have completed 'init' (in the quit/cleanup
# scenario), it is possible we try to write to '$json_filename' before
# it has been set up, which results in an 'ambiguous redirect' error.
json_filename="/dev/null"

# Generate a timestamp in milliseconds since 1st Jan 1970
timestamp_ms() {
	echo $(($(date +%s%N)/1000000))
}

# Intialise the json subsystem
# FIXME - if $1 == "k8s", then we skip some data writes, as we have not
# worked out how to extract useful info yet..
metrics_json_init() {


	# Clear out any previous results
	json_result_array=()

	despaced_name="$(echo ${TEST_NAME} | sed 's/[ \/]/-/g')"
	json_filename="${RESULT_DIR}/${despaced_name}.json"

	local json="$(cat << EOF
	"@timestamp" : $(timestamp_ms)
EOF
)"
	metrics_json_add_fragment "$json"

	# Grab the kubectl version info, which also gets us some server
	# version info
	local json="$(cat << EOF
	"kubectl-version" :
	$(kubectl version -o=json)
EOF
)"
	metrics_json_add_fragment "$json"

	# grab the cluster node info. We *could* grab 'kubectl cluster-info dump' here, but
	# that generates a lot of data, and we would have to trim tne non-JSON logs off the
	# end of it.
	local json="$(cat << EOF
	"kubectl-get-nodes" :
	$(kubectl get nodes -o=json)
EOF
)"
        metrics_json_add_fragment "$json"

	local json="$(cat << EOF
	"date" : {
		"ns": $(date +%s%N),
		"Date": "$(date -u +"%Y-%m-%dT%T.%3N")"
	}
EOF
)"
	metrics_json_add_fragment "$json"

	local json="$(cat << EOF
	"test" : {
		"runtime": "${RUNTIME:-default}",
		"testname": "${TEST_NAME}"
	}
EOF
)"
	metrics_json_add_fragment "$json"

	metrics_json_end_of_system
}

# Save out the final JSON file
metrics_json_save() {

	if [ ! -d ${RESULT_DIR} ];then
		mkdir -p ${RESULT_DIR}
	fi

	local maxelem=$(( ${#json_result_array[@]} - 1 ))
	local json="$(cat << EOF
{
$(for index in $(seq 0 $maxelem); do
	# After the standard system data, we then place all the test generated
	# data into its own unique named subsection.
	if (( index == system_index )); then
		echo "\"${despaced_name}\" : {"
	fi
	if (( index != maxelem )); then
		echo "${json_result_array[$index]},"
	else
		echo "${json_result_array[$index]}"
	fi
done)
	}
}
EOF
)"

	echo "$json" > $json_filename

	# If we have a JSON URL or host/socket pair set up, post the results there as well.
	# Optionally compress into a single line.
	if [[ $JSON_TX_ONELINE ]]; then
		json=$(tr -d '\t\n\r\f' <<< ${json})
	fi

	if [[ $JSON_HOST ]]; then
		echo "socat'ing results to [$JSON_HOST:$JSON_SOCKET]"
		socat -u - TCP:${JSON_HOST}:${JSON_SOCKET} <<< ${json}
	fi

	if [[ $JSON_URL ]]; then
		echo "curl'ing results to [$JSON_URL]"
		curl -XPOST -H"Content-Type: application/json" "$JSON_URL" -d "@-" <<< ${json}
	fi
}

metrics_json_end_of_system() {
	system_index=$(( ${#json_result_array[@]}))
}

# Add a top level (complete) JSON fragment to the data
metrics_json_add_fragment() {
	local data=$1

	# Place on end of array
	json_result_array[${#json_result_array[@]}]="$data"
}

# For building an array in an array element
metrics_json_start_nested_array() {
    json_nested_array=()
}

# Add a (complete) element to the current nested array
metrics_json_add_nested_array_element() {
	local data=$1

	# Place on end of array
	json_nested_array[${#json_nested_array[@]}]="$data"
}

# Add a fragment to the current nested array element
metrics_json_add_nested_array_fragment() {
	local data=$1

	# Place on end of array
	json_nested_array_fragments[${#json_nested_array_fragments[@]}]="$data"
}

# Turn the currently registered nested array fragments into an array element
metrics_json_close_nested_array_element() {

	local maxelem=$(( ${#json_nested_array_fragments[@]} - 1 ))
	local json="$(cat << EOF
	{
		$(for index in $(seq 0 $maxelem); do
			if (( index != maxelem )); then
				echo "${json_nested_array_fragments[$index]},"
			else
				echo "${json_nested_array_fragments[$index]}"
			fi
		done)
	}
EOF
)"

	# And save that to the top level
	metrics_json_add_nested_array_element "$json"

	# Reset the array fragment array ready for a new one
	json_nested_array_fragments=()
}

# Close the current nested array
metrics_json_end_nested_array() {
	local name=$1

	local maxelem=$(( ${#json_nested_array[@]} - 1 ))
	local json="$(cat << EOF
	"$name": [
		$(for index in $(seq 0 $maxelem); do
			if (( index != maxelem )); then
				echo "${json_nested_array[$index]},"
			else
				echo "${json_nested_array[$index]}"
			fi
		done)
	]
EOF
)"

	# And save that to the top level
	metrics_json_add_array_fragment "$json"
}

# Prepare to collect up array elements
metrics_json_start_array() {
	json_array_array=()
}

# Add a (complete) element to the current array
metrics_json_add_array_element() {
	local data=$1

	# Place on end of array
	json_array_array[${#json_array_array[@]}]="$data"
}

# Add a fragment to the current array element
metrics_json_add_array_fragment() {
	local data=$1

	# Place on end of array
	json_array_fragments[${#json_array_fragments[@]}]="$data"
}

# Turn the currently registered array fragments into an array element
metrics_json_close_array_element() {

	local maxelem=$(( ${#json_array_fragments[@]} - 1 ))
	local json="$(cat << EOF
	{
		$(for index in $(seq 0 $maxelem); do
			if (( index != maxelem )); then
				echo "${json_array_fragments[$index]},"
			else
				echo "${json_array_fragments[$index]}"
			fi
		done)
	}
EOF
)"

	# And save that to the top level
	metrics_json_add_array_element "$json"

	# Reset the array fragment array ready for a new one
	json_array_fragments=()
}

# Close the current array
metrics_json_end_array() {
	local name=$1

	local maxelem=$(( ${#json_array_array[@]} - 1 ))
	local json="$(cat << EOF
	"$name": [
		$(for index in $(seq 0 $maxelem); do
			if (( index != maxelem )); then
				echo "${json_array_array[$index]},"
			else
				echo "${json_array_array[$index]}"
			fi
		done)
	]
EOF
)"

	# And save that to the top level
	metrics_json_add_fragment "$json"
}
