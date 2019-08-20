#!/usr/bin/env bash

set -e

# this is needed for the scaling scripts
sudo swupd bundle-add jq

# increase max inotify watchers
cat <<EOT | sudo bash -c "cat > /etc/sysctl.conf"
fs.inotify.max_queued_events=1048576
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=1048576
EOT
sudo sysctl -p

sudo mkdir -p /etc/systemd/system/kubelet.service.d/
cat <<EOT | sudo bash -c "cat > /etc/systemd/system/kubelet.service.d/limits.conf"
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=1048576
TimeoutStartSec=0
MemoryLimit=infinity
EOT

sudo systemctl daemon-reload
sudo systemctl restart kubelet

sudo mkdir -p /etc/systemd/system/containerd.service.d/
cat <<EOT | sudo bash -c "cat > /etc/systemd/system/containerd.service.d/limits.conf"
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=1048576
TimeoutStartSec=0
MemoryLimit=infinity
EOT

sudo systemctl daemon-reload
sudo systemctl restart containerd

# increase limits in kubelet
sudo sed -i 's/^maxPods\:.*/maxPods\: 5000/' /var/lib/kubelet/config.yaml
sudo sed -i 's/^maxOpenFiles\:.*/maxOpenFiles\: 1048576/' /var/lib/kubelet/config.yaml

sudo systemctl daemon-reload
sudo systemctl restart kubelet
