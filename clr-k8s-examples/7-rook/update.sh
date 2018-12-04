#!/bin/bash

ROOK_VER='v0.8.3'

echo "Getting stuff we need..."
curl https://raw.githubusercontent.com/rook/rook/${ROOK_VER}/cluster/examples/kubernetes/ceph/operator.yaml | sed 's|\# - name: FLEXVOLUME_DIR_PATH|- name: FLEXVOLUME_DIR_PATH|g' | sed 's|\#  value: "<PathToFlexVolumes>"|  value: "/var/lib/kubelet/volume-plugins"|g' > 000-operator.yaml
curl https://raw.githubusercontent.com/rook/rook/${ROOK_VER}/cluster/examples/kubernetes/ceph/cluster.yaml | sed 's|useAllDevices: false|useAllDevices: true|g' > 001-cluster.yaml
curl https://raw.githubusercontent.com/rook/rook/${ROOK_VER}/cluster/examples/kubernetes/ceph/storageclass.yaml > 002-storageclass.yaml
