#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

CUR_DIR=$(pwd)
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd $SCRIPT_DIR

function finish {
  cd $CUR_DIR
}
trap finish EXIT

#This only works with kubernetes 1.12+. The kubeadm.yaml is setup
#to enable the RuntimeClass featuregate
sudo -E kubeadm init --config=./kubeadm.yaml

# If this an interactive terminal then wait for user to join workers
if [ -t 0 ]; then
read -p "Join other nodes. Press enter to continue"
fi

rm -rf $HOME/.kube
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#Add support for kata runtime
kubectl apply -f 8-kata/runtimeclass_crd.yaml
while [[ $(kubectl get crd runtimeclasses.node.k8s.io > /dev/null 2>&1) || $? -ne 0 ]];
do echo "Waiting for runtime class CRD"; sleep 2; done
kubectl apply -f 8-kata/kata-runtimeClass.yaml

kubectl apply -f 0-canal/rbac.yaml
kubectl apply -f 0-canal/canal.yaml

#Ensure single node k8s works
if [ $(kubectl get nodes | wc -l) -eq 2 ]; then
kubectl taint nodes --all node-role.kubernetes.io/master-
fi

#Start rook before any other component that requires storage
ROOK_URL=7-rook
kubectl apply -f ${ROOK_URL}/000-operator.yaml
while [[ $(kubectl get crd clusters.ceph.rook.io pools.ceph.rook.io > /dev/null 2>&1) || $? -ne 0 ]];
do echo "Waiting for Rook CRDs"; sleep 2; done
kubectl apply -f ${ROOK_URL}/001-cluster.yaml
kubectl apply -f ${ROOK_URL}/002-storageclass.yaml

kubectl apply -f 1-core-metrics/

kubectl apply -f 2-dashboard/

kubectl apply -f 3-efk/

#Just to allow the CRD to be created. Ideally wait and then run second time
kubectl apply -f 4-kube-prometheus/
while [[ $(kubectl get crd alertmanagers.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com > /dev/null 2>&1) || $? -ne 0 ]];
do echo "Waiting for Prometheus CRDs"; sleep 2; done
kubectl apply -f 4-kube-prometheus/
#Create an ingress load balancer
kubectl apply -f 5-ingres-lb/


#Create a bare metal load balancer.
#kubectl apply -f 6-metal-lb/metallb.yaml

#The config map should be properly modified to pick a range that can live
#on this subnet behind the same gateway (i.e. same L2 domain)
#kubectl apply -f 6-metal-lb/example-layer2-config.yaml


#Expose the dashboards
#kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090 &
#kubectl --namespace monitoring port-forward svc/grafana 3000 &
#kubectl --namespace monitoring port-forward svc/alertmanager-main 9093 &
#kubectl proxy &

