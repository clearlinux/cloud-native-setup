#!/bin/bash
# Usage: sriov.sh ens785f0 ens785f1 ...

for pf in "$@"; do
	echo "Resetting $pf"
	echo 0 | tee /sys/class/net/$pf/device/sriov_numvfs

	NUM_VFS=$(cat /sys/class/net/$pf/device/sriov_totalvfs)
	echo "Enabling $NUM_VFS for $pf"
	echo $NUM_VFS | tee /sys/class/net/$pf/device/sriov_numvfs
	ip link set $pf up
	#for ((i = 0 ; i < ${NUM_VFS} ; i++ )); do ip link set $pf vf $i spoofchk off; done
	for ((i = 0; i < ${NUM_VFS}; i++)); do ip link set dev $pf vf $i state enable; done
done
