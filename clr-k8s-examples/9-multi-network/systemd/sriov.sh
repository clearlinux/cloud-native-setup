#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

OPTIND=1
bind="false"

while getopts ":b" opt; do
	case ${opt} in
	b)
		bind="true"
		;;
	\?)
		echo "Usage: sriov.sh [-b] ens785f0 ens785f1 ..."
		echo "-b	Bind to vfio-pci"
		exit
		;;
	esac
done
shift $((OPTIND - 1))

reset_pf() {
	local pf=$1
	echo "Resetting $pf"
	echo 0 | tee /sys/class/net/$pf/device/sriov_numvfs
}

set_pf() {
	local pf=$1
	local NUM_VFS=$(cat /sys/class/net/$pf/device/sriov_totalvfs)
	echo "Enabling $NUM_VFS for $pf"
	echo $NUM_VFS | tee /sys/class/net/$pf/device/sriov_numvfs
	ip link set $pf up
}

bind_vfs_vfio() {
	if [ $bind != "true" ]; then return; fi
	local pf=$1
	local pci=$(readlink /sys/devices/pci*/*/*/net/$pf/device | awk '{print substr($1,10)}')
	echo "Binding VFs of PF $pf ($pci) to vfio-pci"
	for i in $(ls -l /sys/devices/pci*/*/$pci | awk '"virtfn"==substr($9,1,6) {print substr($11,4)}'); do
		echo $i | tee /sys/bus/pci*/*/$i/driver/unbind
		echo vfio-pci | tee /sys/devices/pci*/*/$i/driver_override
		echo $i | tee /sys/bus/pci/drivers/vfio-pci/bind
	done
}

setup_vfs() {
	local pf=$1
	local NUM_VFS=$(cat /sys/class/net/$pf/device/sriov_totalvfs)
	echo "Setting up VFs of PF $pf"
	for ((i = 0; i < ${NUM_VFS}; i++)); do
		ip link set dev $pf vf $i state enable
		ip link set dev $pf vf $i mac \
			$(printf '00:80:86:%02X:%02X:%02X\n' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
		# ip link set $pf vf $i spoofchk off
	done
}

for pf in "$@"; do
	reset_pf $pf
	set_pf $pf
	bind_vfs_vfio $pf
	setup_vfs $pf
done
