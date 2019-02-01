#!/bin/bash

VERISION="1.2.2"
echo "Install Containerd ${VERSION}"
wget -q https://storage.googleapis.com/cri-containerd-release/cri-containerd-${VERSION}.linux-amd64.tar.gz
sudo tar -C / -xzf cri-containerd-${VERSION}.linux-amd64.tar.gz

# configure runtime classes for Kata
mkdir -p /etc/containerd
sudo cp containerd.conf /etc/containerd/config.toml

# configure kubelet to utilize containerd instead of CRI-O:

## this part may be distribution specific - on Clear Linux we need to edit the system


sudo systemctl start containerd
