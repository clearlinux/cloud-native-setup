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

setup_pf() {
	local pf=$1
	echo "Resetting PF $pf"
	echo 0 | tee /sys/class/net/$pf/device/sriov_numvfs
	local NUM_VFS=$(cat /sys/class/net/$pf/device/sriov_totalvfs)
	echo "Enabling $NUM_VFS VFs for $pf"
	echo $NUM_VFS | tee /sys/class/net/$pf/device/sriov_numvfs
	ip link set $pf up
	sleep 1
}

setup_vfs() {
	local pf=$1
	local pfpci=$(readlink /sys/devices/pci*/*/*/net/$pf/device | awk '{print substr($1,10)}')
	local NUM_VFS=$(cat /sys/class/net/$pf/device/sriov_numvfs)
	for ((idx = 0; idx < NUM_VFS; idx++)); do
		ip link set dev $pf vf $idx state enable
		if [ $bind != "true" ]; then continue; fi

		local vfn="virtfn$idx"
		local vfpci=$(ls -l /sys/devices/pci*/*/$pfpci | awk -v vfn=$vfn 'vfn==$9 {print substr($11,4)}')
		# Capture and set MAC of the VF before unbinding from linux, for later use in CNI
		local mac=$(cat /sys/bus/pci*/*/$vfpci/net/*/address)
		ip link set dev $pf vf $idx mac $mac
		# Bind VF to vfio-pci
		echo $vfpci >/sys/bus/pci*/*/$vfpci/driver/unbind
		echo "vfio-pci" >/sys/devices/pci*/*/$vfpci/driver_override
		echo $vfpci >/sys/bus/pci/drivers/vfio-pci/bind
	done
}

for pf in "$@"; do
	setup_pf $pf
	setup_vfs $pf
done
