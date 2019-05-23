#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

CUR_DIR=$(pwd)
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

function print_usage_exit() {
	exit_code=${1:-0}
	cat <<EOT
Usage: $0 [subcommand]

Subcommands:

$(
		for cmd in "${!command_handlers[@]}"; do
			printf "\t%s:|\t%s\n" "${cmd}" "${command_help[${cmd}]:-Not-documented}"
		done | sort | column -t -s "|"
	)
EOT
	exit "${exit_code}"
}

function finish() {
	cd $CUR_DIR
}
trap finish EXIT

function cluster_init() {
	#This only works with kubernetes 1.12+. The kubeadm.yaml is setup
	#to enable the RuntimeClass featuregate
	sudo -E kubeadm init --config=./kubeadm.yaml

	rm -rf $HOME/.kube
	mkdir -p $HOME/.kube
	sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config

	# If this an interactive terminal then wait for user to join workers
	if [ -t 0 ]; then
		read -p "Join other nodes. Press enter to continue"
	fi

	#Ensure single node k8s works
	if [ $(kubectl get nodes | wc -l) -eq 2 ]; then
		kubectl taint nodes --all node-role.kubernetes.io/master-
	fi
}

function kata() {
	# Install kata artifacts using kata-deploy
	kubectl apply -f 8-kata/deploy/kata-rbac.yaml
	kubectl apply -f 8-kata/deploy/kata-deploy.yaml
	kubectl apply -f 8-kata/
}

function cni() {
	kubectl apply -f 0-canal/rbac.yaml
	kubectl apply -f 0-canal/canal.yaml
}

function metrics() {
	kubectl apply -f 1-core-metrics/
}

function storage() {
	#Start rook before any other component that requires storage
	ROOK_URL=7-rook
	kubectl apply -f ${ROOK_URL}/000-operator.yaml
	while [[ $(kubectl get crd clusters.ceph.rook.io pools.ceph.rook.io >/dev/null 2>&1) || $? -ne 0 ]]; do
		echo "Waiting for Rook CRDs"
		sleep 2
	done
	kubectl apply -f ${ROOK_URL}/001-cluster.yaml
	kubectl apply -f ${ROOK_URL}/002-storageclass.yaml
}

function monitoring() {
	#Just to allow the CRD to be created. Ideally wait and then run second time
	kubectl apply -f 4-kube-prometheus/
	while [[ $(kubectl get crd alertmanagers.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com >/dev/null 2>&1) || $? -ne 0 ]]; do
		echo "Waiting for Prometheus CRDs"
		sleep 2
	done
	kubectl apply -f 4-kube-prometheus/

	#Expose the dashboards
	#kubectl --namespace monitoring port-forward svc/prometheus-k8s 9090 &
	#kubectl --namespace monitoring port-forward svc/grafana 3000 &
	#kubectl --namespace monitoring port-forward svc/alertmanager-main 9093 &
}

function miscellaneous() {
	kubectl apply -f 2-dashboard/
	kubectl apply -f 3-efk/
	#Create an ingress load balancer
	kubectl apply -f 5-ingres-lb/

	#Create a bare metal load balancer.
	#kubectl apply -f 6-metal-lb/metallb.yaml

	#The config map should be properly modified to pick a range that can live
	#on this subnet behind the same gateway (i.e. same L2 domain)
	#kubectl apply -f 6-metal-lb/example-layer2-config.yaml
}

function minimal() {
	cluster_init
	cni
	kata
	metrics
}

function all() {
	minimal
	storage
	monitoring
	miscellaneous
}

declare -A command_handlers
command_handlers[init]=cluster_init
command_handlers[cni]=cni
command_handlers[minimal]=minimal
command_handlers[all]=all
command_handlers[help]=print_usage_exit

declare -A command_help
command_help[init]="Only inits a cluster using kubeadm"
command_help[cni]="Setup network for running cluster"
command_help[minimal]="init + cni +  kata + metrics"
command_help[all]="minimal + storage + monitoring + miscellaneous"
command_help[help]="show this message"

cd $SCRIPT_DIR

cmd_handler=${command_handlers[${1:-none}]:-unimplemented}
if [ "${cmd_handler}" != "unimplemented" ]; then
	"${cmd_handler}"
else
	print_usage_exit 1
fi

