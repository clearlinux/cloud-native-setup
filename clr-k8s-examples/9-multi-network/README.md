# Multi-Network

## Daemonset

We launch a `Daemonset` with an `initContainer` which sets up the CNI
directories on the host with the necessary binaries and configuration files.

> NOTE: SR-IOV devices are not necessary to test multi-network capability

### Customization

The device plugin will register the SR-IOV enabled devices on the host, specified as
`rootDevices` in [sriov-conf.yaml](sriov-conf.yaml). Helper [systemd unit](systemd/sriov.service)
file is provided, which enables SR-IOV for the above `rootDevices`

> NOTE: This assumes homogenous nodes in the cluster

### Pre-req (SR-IOV only)

One each SR-IOV node make sure `VT-d` is enabled in the BIOS.
Setup systemd to bring up VFs on designated interfaces bound to network driver or `vfio-pci`

```bash
# Make sure vfio-pci is loaded on boot
echo 'vfio-pci' | sudo tee /etc/modules-load.d/sriov.conf
sudo systemctl restart systemd-modules-load.service

sudo cp systemd/sriov.sh /usr/bin/sriov.sh
sudo cp systemd/sriov.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sriov.service
```

### Install

To install and configure `multus-cni` on all nodes, along with
`sriov-cni`, `vfioveth-cni` and `sriov-network-device-plugin`

```bash
kubectl apply -f .
kubectl get nodes -o json | jq '.items[].status.allocatable' # should list "intel.com/sriov_*"
```

## Tests

### Default only

To test if default connectivity is working

```bash
kubectl apply -f test/pod.yaml
kubectl exec test -- ip a                        # should see one interface only
```

### Bridge

To test multus with second interface created by `bridge` plugin

```bash
kubectl apply -f test/bridge
kubectl exec test-bridge -- ip a                 # should see two interfaces
ip a show mynet                                  # bridge created on host if it doesnt exist already
```

### SR-IOV

To test multus with second interface created by `sriov` plugin

```bash
kubectl apply -f test/sriov

kubectl exec test-sriov -- ip a                  # second interface is a VF

kubectl exec test-sriov-dpdk -- ip a             # veth pair with details of VF
kubectl exec test-sriov-dpdk -- ls -l /dev/vfio
```
