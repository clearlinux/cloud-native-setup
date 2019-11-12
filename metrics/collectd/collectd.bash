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

	# create collectd-config configmap
	kubectl create configmap collectd-config --from-file=${COLLECTD_DIR}/collectd.conf

	# Launch our stats gathering pod
	kubectl apply -f ${COLLECTD_DIR}/${collectd_pod}.yaml
	kubectl rollout status --timeout=${wait_time}s daemonset/${collectd_pod}

	# attempting to provide buffer for collectd to be installed and running,
    # and CPU collection to build adequate history
	sleep 12
}

cleanup_stats() {
	# attempting to provide buffer for collectd CPU collection to record adequate history
	sleep 6

	# get logs before shutting down stats daemonset
	while read -u 3 name node; do
		kubectl exec -ti $name -- sh -c "cd /opt/collectd; tar -czvf localhost.tar.gz localhost"
		# make a backup on the host in-case collection fail
		kubectl exec -ti $name -- sh -c "mkdir -p /mnt/opt/collectd"
		kubectl exec -ti $name -- sh -c "cp /opt/collectd/localhost.tar.gz /mnt/opt/collectd/localhost.tar.gz"
		kubectl cp $name:/opt/collectd/localhost.tar.gz ${RESULT_DIR}/${node}.tar.gz
	done 3< <(kubectl get pods --selector name=collectd-pods -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"')

	kubectl delete daemonset --wait=true --timeout=${delete_wait_time}s "${collectd_pod}" || true

	# remove configmap
	kubectl delete configmap collectd-config
}
