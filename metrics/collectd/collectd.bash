#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

THIS_FILE=$(readlink -f ${BASH_SOURCE[0]})
COLLECTD_DIR=${THIS_FILE%/*}

collectd_pod="collectd"

init_stats() {
	local wait_time=$1

	# create collectd-config configmap, delete old if there is one
	kubectl get configmap collectd-config >/dev/null 2>&1 && kubectl delete configmap collectd-config
	kubectl create configmap collectd-config --from-file=${COLLECTD_DIR}/collectd.conf

	# if there is collectd daemonset already running, delete it
	# to make sure that the latest configmap will be used.
	kubectl get daemonset collectd >/dev/null 2>&1 && kubectl delete daemonset --wait=true --timeout=${delete_wait_time}s "${collectd_pod}"

	# Launch our stats gathering pod
	kubectl apply -f ${COLLECTD_DIR}/${collectd_pod}.yaml
	kubectl rollout status --timeout=${wait_time}s daemonset/${collectd_pod}

	# clear existing collectd output
	while read -u 3 name node; do
		kubectl exec -ti $name -- sh -c "rm -rf /mnt/opt/collectd/run/localhost/*"
	done 3< <(kubectl get pods --selector name=collectd-pods -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')

	# attempting to provide buffer for collectd to be installed and running,
	# and CPU collection to build adequate history
	sleep 12
}

cleanup_stats() {
	# attempting to provide buffer for collectd CPU collection to record adequate history
	sleep 6

	# get logs before shutting down stats daemonset
	while read -u 3 name node; do
		kubectl exec -ti $name -- sh -c "cd /mnt/opt/collectd/run; rm -f ../localhost.tar.gz; tar -czvf ../localhost.tar.gz localhost"
		kubectl cp $name:/mnt/opt/collectd/localhost.tar.gz ${RESULT_DIR}/${node}.tar.gz
		kubectl exec -ti $name -- sh -c "rm -rf /mnt/opt/collectd/run"
	done 3< <(kubectl get pods --selector name=collectd-pods -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')

	kubectl delete daemonset --wait=true --timeout=${delete_wait_time}s "${collectd_pod}" || true

	# remove configmap
	kubectl delete configmap collectd-config
}
