#!/usr/bin/env bash

# Runs upstream k8s e2e tests against existing cloud native basic cluster
# Requires cluster to already be up
# To specify a parameter for --ginkgo.focus as described below, provide a focus as the first argument to this script
#     https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md#building-kubernetes-and-running-the-tests
# One example would be Feature:Performance. The script will add square brackets for you
# For other examples of values, see
#     https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md#kinds-of-tests

if [ ! -z $1 ]
then
    FOCUS=$1
    echo Running e2e tests where spec matches $1
else
    echo Running all e2e tests, this will take a long time
fi

sudo swupd bundle-add go-basic

go get -d k8s.io/kubernetes
go get -u k8s.io/test-infra/kubetest

set -o errexit
set -o pipefail
set -o nounset

cd /home/clear/go/src/k8s.io/kubernetes

PATH=$PATH:/home/clear/go/bin

API_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"kubernetes\")].cluster.server}")
API_SERVER_VERSION=$(kubectl version --short | grep -E 'Server' | sed 's/Server Version: //')

if [ -z $FOCUS ]
then
    sudo -E kubetest --test --test_args="--kubeconfig=${HOME}/.kube/config --host=$API_SERVER" --extract=$API_SERVER_VERSION --provider=local
else
    sudo -E kubetest --test --test_args="--kubeconfig=${HOME}/.kube/config --host=$API_SERVER --ginkgo.focus=\[$FOCUS\]" --extract=$API_SERVER_VERSION --provider=local
fi

