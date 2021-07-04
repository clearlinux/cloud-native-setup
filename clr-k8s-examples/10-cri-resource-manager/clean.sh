#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Uninstall and stop the CRI Resource Manager service

set -o errexit
set -o nounset

# Kubelet
KUBEADM_FLAGS="/var/lib/kubelet/kubeadm-flags.env"
sudo rm -f /etc/systemd/system/kubelet.service.d/99-cri-resource-manager.conf
sudo systemctl daemon-reload
sudo systemctl restart kubelet

if sudo test -f "$KUBEADM_FLAGS.bkp" ; then
    sudo mv $KUBEADM_FLAGS.bkp $KUBEADM_FLAGS
fi

# CRI Resource Manager
sudo systemctl stop cri-resource-manager
sudo systemctl disable cri-resource-manager
