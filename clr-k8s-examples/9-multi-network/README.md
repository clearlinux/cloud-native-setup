# Multi-Network

## Daemonset

We launch a `Daemonset` with an `initContainer` which sets up the CNI
directories on the host with the necessary binaries and configuration files.

### Customization

Replace `flannel` configuration in the delegates section with contents of your
default network's cni configuration in [multus-conf.yaml](clr-k8s-examples/9-multi-network/multus-conf.yaml).
The device plugin, will discover any SR-IOV enabled devices on the host as per the
configuration in [sriov-conf.yaml](clr-k8s-examples/9-multi-network/sriov-conf.yaml).

> NOTE: This assumes homogenous nodes in the cluster

### Install

To install and configure `multus-cni` on all nodes, along with `sriov-cni` and
`sriov-network-device-plugin` :

```bash
kubectl apply -f .
kubectl get nodes -o json | jq '.items[].status.allocatable' # should list "intel.com/sriov"
```

## Tests

### Default only

To test if default connectivity is working

```bash
kubectl apply -f test/pod.yaml
kubectl exec test -- ip a        # should see one interface only
```

### Bridge

To test multus with second interface created by `bridge` plugin

```bash
kubectl apply -f test/bridge
kubectl exec test-bridge -- ip a # should see two interfaces
ip a show mynet                  # bridge created if it doesnt exist already
```

### SR-IOV

To test multus with second interface created by `sriov` plugin

```bash
kubectl apply -f test/sriov
kubectl exec test-sriov -- ip a  # second interface is a VF
```
