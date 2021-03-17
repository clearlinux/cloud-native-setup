# How to setup the cluster

## Prerequisite
This setup currently will work with Kubernetes 1.14 & above. Any version of Kubernetes before that might work, but is not guaranteed.

## QUICK NOTE
The version of Kubernetes* was bumped from 1.17.7 to 1.19.4 in Clear Linux* OS release 34090. The [guide](https://docs.01.org/clearlinux/latest/guides/clear/k8s-migration.html) and the Clear Linux OS bundle k8s-migration were created to help facilitate migration of a cluster from 1.17.x to the latest 1.19.x .

The new Clear Linux OS bundle k8s-migration was added in Clear Linux* OS release 34270. Please follow the guide for an upgrade.

## Sample multi-node vagrant setup

To be able to test this tool, you can create a 3-node vagrant setup. In this tutorial, we will talk about using [libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt), but you can use any hypervisor that you are familiar with.

## Install vagrant

Follow instructions in the [Vagrant docs](https://www.vagrantup.com/intro/getting-started/install.html#installing-vagrant)

Or, follow our [detailed steps](vagrant.md)

Now you have a 3 node cluster up and running. Each of them have 4 vCPU, 8GB Memory, 2x10GB disks, 1 additional private network.
Customize the setup using environment variables. E.g., `NODES=2 MEMORY=16384 CPUS=8 vagrant up --provider=libvirt`

To login to the master node and change to this directory

```bash
vagrant ssh clr-01
cd clr-k8s-examples
```

## Setup the nodes in the cluster

Run [`setup_system.sh`](setup_system.sh) once on each and every node (master and workers)
to ensure Kubernetes works on it.

This script ensures the following

* Installs the bundles the Clearlinux needs to support Kubernetes, CRIO and Kata
* Customizes the system to ensure correct defaults are setup (IP Forwarding, Swap off,...)
* Ensures all the dependencies are loaded on boot (kernel modules)

> NOTE: This step is done automatically if using vagrant. The [`setup_system.sh`](setup_system.sh)
script uses the runtime specified in the `RUNNER` environment variable and defaults to `crio`. To use the
`containerd` runtime, set the `RUNNER` environment variable to `containerd`.

In case of vagrant, if you want to spin up VM's using different environment variable than declared in [`setup_system.sh`],
specify when performing vagrant up. E.g., `RUNNER=containerd vagrant up`

### Specify a version of Clear Linux

To specify a particular version of Clear Linux to use, set the CLRK8S_CLR_VER environment variable to the desired
version before starting setup_system.sh (e.g. `CLRK8S_CLR_VER=31400 ./setup_system.sh`)

### Configuration for high numbers of pods per node

In order to enable running greater than 110 pods per node, set the environment
variable `HIGH_POD_COUNT` to any non-empty value.

> NOTE: Use this configuration when utilizing the [metrics](../metrics) tooling in this repo.

### Enabling experimental firecracker support

> EXPERIMENTAL: Optionally run [`setup_kata_firecracker.sh`](setup_kata_firecracker.sh) to be
able to use firecracker VMM with Kata.

The firecracker setup switches the setup to use a sparse file backed loop device for
devicemapper storage. This should not be used for production.

> NOTE: This step is done automatically if using vagrant.

### For HA, setup the load balancer node

Ideally, the load balancer node will be a separate node. However, one of the
master nodes can also serve as the load balancer for the cluster. [HAProxy](https://www.haproxy.org/)
is used in these instructions.

```bash
sudo swupd bundle-add haproxy
sudo systemctl enable haproxy
```

Edit the master IP addresses and load balancer address and ports in [`haproxy.cfg.example`](haproxy.cfg.example)
to match the IPs for the new cluster. If using a master node for the load balancer
make sure that the `frontend bind` port is different than the Kubernetes API port, 6443.
If using a separate machine for load balancing, the port can be 6443 if desired.

```bash
sudo mkdir -p /etc/haproxy
sudo cp haproxy.cfg.example /etc/haproxy/haproxy.cfg
sudo systemctl start haproxy
```

## Bring up the master

Run [`create_stack.sh`](create_stack.sh) on the master node. This sets up the
master and also uses kubelet config via [`kubeadm.yaml`](kubeadm.yaml)
to propagate cluster wide kubelet configuration to all workers. Customize it if
you need to setup other cluster wide properties.

There are different flavors to install, run `./create_stack.sh help` to get
more information.

> NOTE: Before running [`create_stack.sh`](create_stack.sh) script, make sure to export
the necessary environment variables if needed to be changed. By default it will use
`CLRK8S_CNI` to be canal, and `CLRK8S_RUNNER` to be crio. Cilium is tested only in the
Vagrant. If creating an HA cluster, make sure to specify `LOAD_BALANCER_IP` and
`LOAD_BALANCER_PORT`.

```bash
# default shows help
./create_stack.sh <subcommand>
```

In order to enable running greater than 110 pods per node, set the environment
variable `HIGH_POD_COUNT` to any non-empty value.

If creating an HA cluster, join the other master nodes to the cluster.

```bash
kubeadm join <load-balancer-ip>:<load-balancer-port> --token <token> --discovery-token-ca-cert-hash <hash> \
    --control-plane --certificate-key <certificate-key> --cri-socket=/run/crio/crio.sock
```

## Join Workers to the cluster

```bash
kubeadm join <master-ip>:<master-port> --token <token> --discovery-token-ca-cert-hash <hash> --cri-socket=/run/crio/crio.sock
```

Note: Remember to append `--cri-socket=/run/crio/crio.sock` to the join command generated by the master.

If creating an HA cluster, join the other worker nodes to the cluster. The same way,
but replacing the `<master-ip>:<master-port>` with `<load-balancer-ip>:<load-balancer-port>`.

On workers just use the join command that the master spits out. There nothing
else you need to run on the worker. All the other Kubernetes customizations are pushed
in from master via the values setup in the `kubeadm.yaml` file.

So if you want to customize the kubelet on the master or the workers (things
like resource reservations etc), update this file (when the cluster is created).
The master will push this configuration automatically to every worker node that joins in.

## Running Kata Workloads

The cluster is setup out of the box to support Kata via runtime class. Clearlinux
will also setup kata automatically on all nodes. So running a workload with
runtime class set to "kata" will launch the POD/Deployment with Kata.

An example is

`kubectl apply -f tests/deploy-svc-ing/test-deploy-kata-qemu.yaml`

### Running Kata Workloads with Firecracker

> EXPERIMENTAL: If firecracker setup has been enabled, runtime class set to "kata-fc" will launch the POD/Deployment
with firecracker as the isolation mechanism for Kata.

An example is

`kubectl apply -f tests/deploy-svc-ing/test-deploy-kata-fc.yaml`

## Making Kata the default runtime using admission controller

If you want to run a cluster where kata is used
by default, except for workloads we know for sure will not work with kata, using
[admission webhook](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#admission-webhooks)
and sample admission controller, follow `admit-kata` [README.md](admit-kata/README.md)

## Accessing control plane services

### Pre-req

You need to have credentials of the cluster, on the computer
you will be accessing the control plane services from. If it is not under
`$HOME/.kube`, set `KUBECONFIG` environment variable for `kubectl` to find.

### Dashboard

```bash
kubectl proxy # starts serving on 127.0.0.1:8001
```

Dashboard is available at this URL
http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy

### Kibana

Start proxy same as above. Kibana is available at this URL
http://localhost:8001/api/v1/namespaces/kube-system/services/kibana-logging/proxy/app/kibana

### Grafana

```bash
kubectl -n monitoring port-forward svc/grafana 3000
```

Grafana is available at this URL http://localhost:3000 . Default credentials are
`admin/admin`. Upon entering you will be asked to chose a new password.

## Cleaning up the cluster (Hard reset to a clean state)

Run `reset_stack.sh` on all the nodes

## Additional Components

### Rook
The default Rook configuration provided is intended for testing purposes only
and is not suitable for a production environment. By default Rook is configured
to provide local storage (/var/lib/rook) and will be provisioned differently
depending on whether or not you startup a single node Kubernetes cluster, or
a multiple node Kubernetes cluster. 

- When starting up a single node Kubernetes cluster, Rook will be configured
to start up a single replica, and will allow multiple monitors on the same node.
- When multiple Kubernetes worker nodes are detected, Rook will be configured
to startup a replica on each available node and will schedule monitor processes
on separate nodes providing greater reliability.
