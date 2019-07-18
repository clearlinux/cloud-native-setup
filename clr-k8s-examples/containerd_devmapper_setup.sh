#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

sudo rm -rf /var/lib/containerd/devmapper/data-disk.img
sudo rm -rf /var/lib/containerd/devmapper/meta-disk.img
sudo mkdir -p /var/lib/containerd/devmapper
sudo truncate --size 10G /var/lib/containerd/devmapper/data-disk.img
sudo truncate --size 10G /var/lib/containerd/devmapper/meta-disk.img

sudo mkdir -p /etc/systemd/system

cat<<EOT | sudo tee /etc/systemd/system/containerd-devmapper.service
[Unit]
Description=Setup containerd devmapper device
DefaultDependencies=no
After=systemd-udev-settle.service
Before=lvm2-activation-early.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=-/sbin/losetup /dev/loop20 /var/lib/containerd/devmapper/data-disk.img
ExecStart=-/sbin/losetup /dev/loop21 /var/lib/containerd/devmapper/meta-disk.img

[Install]
WantedBy=local-fs.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now containerd-devmapper

# Time to setup the thin pool for consumption.
# The table arguments are such.
# start block in the virtual device
# length of the segment (block device size in bytes / Sector size (512)
# metadata device
# block data device
# data_block_size Currently set it 512 (128KB)
# low_water_mark. Copied this from containerd snapshotter test setup
# no. of feature arguments
# Skip zeroing blocks for new volumes.
sudo dmsetup create contd-thin-pool \
  --table "0 2097152 thin-pool /dev/loop21 /dev/loop20 512 32768 1 skip_block_zeroing"

sudo mkdir -p /etc/containerd/
if [ -f /etc/containerd/config.toml ]
then
  sudo sed -i 's|^\(\[plugins\]\).*|\1\n  \[plugins.devmapper\]\n    pool_name = \"contd-thin-pool\"\n    base_image_size = \"512MB\"|' /etc/containerd/config.toml
else
  cat<<EOT | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.devmapper]
    pool_name = "contd-thin-pool"
    base_image_size = "512MB"
EOT
fi

sudo systemctl restart containerd
