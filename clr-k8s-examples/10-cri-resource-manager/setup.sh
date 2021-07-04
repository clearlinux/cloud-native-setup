#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Configure CRI Resource Manager as container runtime endpoint for kubelet

set -o errexit
set -o nounset

CRI_RESMGR_SOCKET="/var/run/cri-resmgr/cri-resmgr.sock"
KUBEADM_FLAGS="/var/lib/kubelet/kubeadm-flags.env"

if sudo test -S "$CRI_RESMGR_SOCKET" ; then
	sudo mkdir -p /etc/systemd/system/kubelet.service.d/
	cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/99-cri-resource-manager.conf
[Service]
Environment=KUBELET_EXTRA_ARGS=
Environment=KUBELET_EXTRA_ARGS="--container-runtime remote --container-runtime-endpoint unix://${CRI_RESMGR_SOCKET}"
EOF

	if sudo test -f "$KUBEADM_FLAGS" ; then
	    sudo mv $KUBEADM_FLAGS $KUBEADM_FLAGS.bkp
	fi

	sudo systemctl daemon-reload
	sudo systemctl restart cri-resource-manager
	sudo systemctl restart kubelet
fi
