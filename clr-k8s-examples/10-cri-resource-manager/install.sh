#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Install and start the CRI Resource Manager service

set -o errexit
set -o nounset

RUNNER=${RUNNER:-"containerd"}
CRI_RESMGR_POLICY=${CRI_RESMGR_POLICY:-"null"}
CRI_RESMGR_POLICY_OPTIONS=${CRI_RESMGR_POLICY_OPTIONS:-"-dump='reset,full:.*' -dump-file=/tmp/cri.dump"}
CRI_RESMGR_DEBUG_OPTIONS=${CRI_RESMGR_DEBUG_OPTIONS:-""}

curl https://raw.githubusercontent.com/obedmr/cri-resource-manager/master/godownloader.sh | bash
sudo cp ./bin/* /usr/bin/

runtime_socket=$(sudo find /run/ -iname $RUNNER.sock | head -1)
CRI_RESMGR_POLICY_OPTIONS+=" -runtime-socket=$runtime_socket -image-socket=$runtime_socket"

sudo mkdir -p /etc/sysconfig/
cat <<EOF | sudo tee /etc/sysconfig/cri-resource-manager
POLICY=$CRI_RESMGR_POLICY
POLICY_OPTIONS=$CRI_RESMGR_POLICY_OPTIONS
DEBUG_OPTIONS=$CRI_RESMGR_DEBUG_OPTIONS
EOF

sudo mkdir -p /etc/systemd/system/
curl https://raw.githubusercontent.com/obedmr/cri-resource-manager/master/cmd/cri-resmgr/cri-resource-manager.service | sudo tee /etc/systemd/system/cri-resource-manager.service

sudo sed -i '/Requires=/d' /etc/systemd/system/cri-resource-manager.service
sudo systemctl daemon-reload
sudo systemctl restart cri-resource-manager.service
sudo systemctl enable cri-resource-manager.service

