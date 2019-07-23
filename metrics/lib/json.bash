#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Helper routines for generating JSON formatted results.

declare -a json_result_array
declare -a json_array_array

# Generate a timestamp in nanoseconds since 1st Jan 1970
timestamp_ns() {
	local t
	local s
	local n
	local ns

	t="$(date +%-s:%-N)"
	s=$(echo $t | awk -F ':' '{print $1}')
	n=$(echo $t | awk -F ':' '{print $2}')
	ns=$(( (s * 1000000000) + n ))

	echo $ns
}

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

	local json="$(cat << EOF
	"env" : {
		"RuntimeVersion": "$RUNTIME_VERSION",
		"RuntimeCommit": "$RUNTIME_COMMIT",
		"RuntimeConfig": "$RUNTIME_CONFIG_PATH",
		"Hypervisor": "$HYPERVISOR_PATH",
		"HypervisorVersion": "$HYPERVISOR_VERSION",
		"Proxy": "$PROXY_PATH",
		"ProxyVersion": "$PROXY_VERSION",
		"Shim": "$SHIM_PATH",
		"ShimVersion": "$SHIM_VERSION",
		"machinename": "$(uname -n)"
	}
EOF
)"

	metrics_json_add_fragment "$json"

	local json="$(cat << EOF
	"date" : {
		"ns": $(timestamp_ns),
		"Date": "$(date -u +"%Y-%m-%dT%T.%3N")"
	}
EOF
)"
	metrics_json_add_fragment "$json"

	local json="$(cat << EOF
	"test" : {
		"runtime": "${RUNTIME}",
		"testname": "${TEST_NAME}"
	}
EOF
)"
	metrics_json_add_fragment "$json"

	# Now add a runtime specific environment section if we can
	if [ "$1" == "k8s" ]; then
		# FIXME - add k8s specific data dump here.
		true
	else
		local iskata=$(is_a_kata_runtime "$RUNTIME")
		if [ "$iskata" == "1" ]; then
			local rpath="$(get_docker_kata_path $RUNTIME)"
			local json="$(cat << EOF
	"kata-env" :
	$($rpath kata-env --json)
EOF
)"
			metrics_json_add_fragment "$json"
		else
			if [ "$RUNTIME" == "runc" ]; then
				local output=$(docker-runc -v)
				local runcversion=$(grep version <<< "$output" | sed 's/runc version //')
				local runccommit=$(grep commit <<< "$output" | sed 's/commit: //')
				local json="$(cat << EOF
	"runc-env" :
	{
		"Version": {
			"Semver": "$runcversion",
			"Commit": "$runccommit"
		}
	}
EOF
)"
				metrics_json_add_fragment "$json"
			else
				warning "Unrecognised runtime ${RUNTIME} - no env extracted"
			fi
		fi
	fi

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
		json="$(sed 's/[\n\t]//g' <<< ${json})"
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
