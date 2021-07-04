# CRI Resource Manager
CRI Resource Manager serves as a relay/proxy between kubelet and the container runtime, relaying requests and responses back and forth between these two, potentially altering requests as they fly by.

This document explains a very simple use case for the `cri-resource-manager`, for more details and tweaks
on CRI Resource Manager service, you can go to https://github.com/intel/cri-resource-manager.

## Install

[`install.sh`](install.sh) script will download the binary and install it as an `systemd` service unit. This script will be executed in all nodes where `cri-resmgr` is required.

Below you can see the available variables you can use to customize the usage of your CRI Resource Manager service.

| Variable                    | Description                               | Default Value                                    |
|-----------------------------|-------------------------------------------|--------------------------------------------------|
| `RUNNER`                    | Default Container Runtime                 | `containerd`                                     |
| `CRI_RESMGR_POLICY`         | CRI Resource Manager Policy type          | `null`                                           |
| `CRI_RESMGR_POLICY_OPTIONS` | CRI Resource Manager extra policy options | `-dump='reset,full:.*' -dump-file=/tmp/cri.dump` |
| `CRI_RESMGR_DEBUG_OPTIONS`  | CRI Resource Manager debugging options    | `<none>`                                         |

**Example:**
```bash
$ RUNNER=containerd ./install.sh
```

Verify that the cri-resource-manager service is actually running.

```bash
$ systemctl status cri-resource-manager
```

Verify that the `cri-resmgr` socket is created, it will indicate that `cri-resource-manager` is ready to receive requests.
```bash
$ sudo ls -la /var/run/cri-resmgr/cri-resmgr.sock
```

## Setup as a container runtime in `kubelet`

The [`setup.sh`](setup.sh) script will configure the `kubelet` service to use the `cri-resource-manager` relay as its remote container runtime. This script will be executed in all nodes where `cri-resmgr` is being configured.

**Example:**
```bash
$ ./setup.sh
```

Kubelet service should be restarted and now using `cri-resource-manager` as its container runtime

```bash
$ ps aux | grep kubelet | grep container-runtime
root       28703  1.7  2.0 1246348 83088 ?       Ssl  20:03   0:06 /usr/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --config=/var/lib/kubelet/config.yaml --container-runtime remote --container-runtime-endpoint unix:///var/run/cri-resmgr/cri-resmgr.sock
```

`cri-resource-manager` service's logs will be located at `/tmp/cri.dump`

```bash
$ tail /tmp/cri.dump
```

## Cleanup

The [`clean.sh`](clean.sh) will first clean the `kubelet` service as it was before the `cri-resource-manager` and restarts `kubelet` service. This script will be executed in all nodes where `cri-resmgr` is being uninstalled.
Then, it will proceed to stop the `cri-resource-manager` service.

**Example:**
```bash
$ ./clean.sh
```

## More kubernetes native approach (experimental)

In case that you're interested in a more Kubernetes native way of deploying the CRI Resource manager, take a look on: https://github.com/intel/cri-resource-manager/pull/55