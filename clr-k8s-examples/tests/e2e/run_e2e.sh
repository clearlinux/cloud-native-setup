#!/usr/bin/env bash

# Runs upstream k8s e2e tests against existing cloud native basic cluster
# Requires cluster to already be up
# To specify a parameter for --ginkgo.focus as described below, provide a focus as the first argument to this script
#     https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md#building-kubernetes-and-running-the-tests
# One example would be Feature:Performance. The script will add square brackets for you
# For other examples of values, see
#     https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md#kinds-of-tests

set -o errexit
set -o pipefail

if [ ! -z $1 ]
then
    FOCUS=$1
    echo Running e2e tests where spec matches $1
else
    echo Running all e2e tests, this will take a long time
fi

GO_INSTALLED=$(sudo swupd bundle-list | grep go-basic)
if [ -z $GO_INSTALLED ]
then
    echo Installing go-basic bundle
    sudo swupd bundle-add go-basic
else
    echo Skipping go-basic bundle installation
fi

if [ -z $GOPATH ] ; then GOPATH=$HOME/go; fi
if [ -z $GOBIN ] ; then GOBIN=$HOME/go/bin; fi

echo Getting kubetest
go get -u k8s.io/test-infra/kubetest

cd $GOPATH/src/k8s.io

if [ -d kubernetes ]
then
    cd kubernetes
    echo Checking status of existing k8s repo clone
    git status kubernetes
else
    echo Cloning upstream k8s repo
    git clone https://github.com/kubernetes/kubernetes.git
    cd kubernetes
fi

PATH=$PATH:$GOBIN

API_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"kubernetes\")].cluster.server}")
CLIENT_VERSION=$(kubectl version --short | grep -E 'Client' | sed 's/Client Version: //')

echo Running kubetest

if [ -z $FOCUS ]
then
    echo sudo -E kubetest --test --test_args="--kubeconfig=${HOME}/.kube/config --host=$API_SERVER" --extract=$CLIENT_VERSION --provider=local 
    sudo -E kubetest --test --test_args="--kubeconfig=${HOME}/.kube/config --host=$API_SERVER" --extract=$CLIENT_VERSION --provider=local
else
    echo sudo -E kubetest --test --test_args="--kubeconfig=${HOME}/.kube/config --host=$API_SERVER --ginkgo.focus=\[$FOCUS\]" --extract=$CLIENT_VERSION --provider=local
    sudo -E kubetest --test --test_args="--kubeconfig=${HOME}/.kube/config --host=$API_SERVER --ginkgo.focus=\[$FOCUS\]" --extract=$CLIENT_VERSION --provider=local
fi

