#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

# Firecracker can only work with devicemapper
# Setup a sparse disk to be used for devicemapper
sudo rm -f /var/lib/crio/devicemapper/disk.img
sudo mkdir -p /var/lib/crio/devicemapper
sudo truncate /var/lib/crio/devicemapper/disk.img --size 10G

# Ensure that this disk is loop mounted at each boot
sudo mkdir -p /etc/systemd/system

cat <<EOT | sudo tee /etc/systemd/system/devicemapper.service
[Unit]
Description=Setup CRIO devicemapper
DefaultDependencies=no
After=systemd-udev-settle.service
Before=lvm2-activation-early.service
Wants=systemd-udev-settle.service

[Service]
ExecStart=-/sbin/losetup /dev/loop8 /var/lib/crio/devicemapper/disk.img
RemainAfterExit=true
Type=oneshot

[Install]
WantedBy=local-fs.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now devicemapper

sudo sed -i 's/storage_driver = \"overlay\"/storage_driver = \"devicemapper\"\
storage_option = [\
  \"dm.basesize=8G\",\
  \"dm.directlvm_device=\/dev\/loop8\",\
  \"dm.directlvm_device_force=true\",\
  \"dm.override_udev_sync_check=true",\
  \"dm.fs=ext4\"\
]/g' /etc/crio/crio.conf

sudo systemctl restart crio || true
