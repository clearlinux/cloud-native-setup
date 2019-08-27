#!/bin/bash
name=$( echo $(kubectl get po -o name -n rook-ceph | grep tools) | cut -c 5-)
kubectl exec -it "${name}" -n rook-ceph -- ceph status
