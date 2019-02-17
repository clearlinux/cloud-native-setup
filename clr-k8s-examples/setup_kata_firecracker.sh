#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

sudo mkdir -p /etc/kata-containers

# Setup a configuration to be used by firecracker
cat <<EOT | sudo tee /etc/kata-containers/configuration_firecracker.toml
[hypervisor.firecracker]
path = "/usr/bin/firecracker"
kernel = "/usr//share/kata-containers/vmlinux.container"
image = "/usr//share/kata-containers/kata-containers.img"
kernel_params = ""
default_vcpus = 1
default_memory = 4096
default_maxvcpus = 0
default_bridges = 1
block_device_driver = "virtio-mmio"
disable_block_device_use = false
enable_debug = true
use_vsock = true

[shim.kata]
path = "/usr//libexec/kata-containers/kata-shim"

[agent.kata]

[runtime]
internetworking_model="tcfilter"
EOT

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

# For now till we address https://github.com/kubernetes-sigs/cri-o/issues/1991
# use a shell script to expose firecracker through kata
cat <<EOT | sudo tee /usr/bin/kata-fc
#!/bin/bash

/usr/bin/kata-runtime --kata-config /etc/kata-containers/configuration_firecracker.toml "\$@"
EOT

sudo chmod +x /usr/bin/kata-fc

# Add firecracker as a second runtime
# Also setup crio to use devicemapper

sudo mkdir -p /etc/crio/
if [ ! -f /etc/crio/crio.conf ]; then
  sudo cp /usr/share/defaults/crio/crio.conf /etc/crio/crio.conf
fi

echo -e "\n[crio.runtime.runtimes.kata-qemu]\nruntime_path = \"/usr/bin/kata-runtime\"" | sudo tee -a /etc/crio/crio.conf
echo -e "\n[crio.runtime.runtimes.kata-fc]\nruntime_path = \"/usr/bin/kata-fc\"" | sudo tee -a /etc/crio/crio.conf

sudo sed -i 's|\(\[crio\.runtime\]\)|\1\nmanage_network_ns_lifecycle = true|' /etc/crio/crio.conf

sudo sed -i 's/storage_driver = \"overlay\"/storage_driver = \"devicemapper\"\
storage_option = [\
  \"dm.basesize=8G\",\
  \"dm.directlvm_device=\/dev\/loop8\",\
  \"dm.directlvm_device_force=true\",\
  \"dm.override_udev_sync_check=true",\
  \"dm.fs=ext4\"\
]/g' /etc/crio/crio.conf

sudo systemctl restart crio || true
