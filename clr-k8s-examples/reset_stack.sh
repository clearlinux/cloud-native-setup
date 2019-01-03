#!/usr/bin/env bash

set -o nounset

#Cleanup
sudo -E kubeadm reset -f --cri-socket="/var/run/crio/crio.sock"

for ctr in $(sudo crictl ps --quiet); do
	sudo crictl stop "$ctr"
	sudo crictl rm "$ctr"
done
for pod in $(sudo crictl pods --quiet); do
	sudo crictl stopp "$pod"
	sudo crictl rmp "$pod"
done

#Forcefull cleanup all artifacts
#This is needed is things really go wrong
sudo systemctl stop kubelet
sudo systemctl stop crio
sudo pkill -9 qemu
sudo pkill -9 kata
sudo pkill -9 kube
sudo find /var/lib/containers/storage/overlay/ -path "*/merged" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-serviceaccount" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-proxy" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-termination-log" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-hosts" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-certs" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-hostname" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-resolv.conf" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*-shm" -exec umount {} \;
sudo find /run/kata-containers/shared/sandboxes/ -path "*/*/rootfs" -exec umount {} \;
sudo find /run/containers/storage/overlay-containers/ -path "*/userdata/shm" -exec umount {} \;
sudo umount /run/netns/cni-*
sudo -E bash -c "rm -r /var/lib/containers/storage/overlay*/*"
sudo -E bash -c "rm -r /var/lib/cni/networks/*"
sudo -E bash -c "rm -r /var/run/kata-containers/*"
sudo rm -rf /var/lib/rook

sudo systemctl daemon-reload
sudo systemctl enable kubelet crio
sudo systemctl restart crio
sudo systemctl restart kubelet

sudo -E kubeadm reset -f --cri-socket="/var/run/crio/crio.sock"
