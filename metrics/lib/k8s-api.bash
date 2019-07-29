#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Helper routines for talking to k8s over its API, via http/curl

API_ADDRESS="http://127.0.0.1"
API_PORT="8090"
PROXY_CMD="kubectl proxy --port=${API_PORT}"
clean_up_proxy=false

k8s_api_init() {
	# check if kubectl proxy is already running. If it is use the port,
	# specified, otherwise start kubectl proxy command.
	if [ $use_api != "no" ]; then
		# assuming command was called "kubectl proxy --port=####"
		# FIXME make this more flexible for --port parameter being in a different order
		local port
		port=$(ps -ef | awk '$8 == "kubectl" && $9 == "proxy" {print $10}' | cut -b1-7 --complement)
		if [ -z $port ]; then
			echo "starting kubectl proxy"
			clean_up_proxy=true
			${PROXY_CMD} &
		else
			echo "found proxy port: ${port}"
			API_PORT=$port
		fi
	fi
}

k8s_api_shutdown() {
	# if this script launched the proxy, clean it up to prevent hang on exit
	if [ "$clean_up_proxy" = "true" ]; then
		echo "cleaning up kubectl proxy"
		kill $(pgrep -f "${PROXY_CMD}")
	fi
}

# get the number of nodes in the "Ready" state
get_num_nodes() {
	n=$(kubectl get nodes --no-headers=true | awk '$2 == "Ready" {print $1}' | wc -l)
	echo "$n"
}

