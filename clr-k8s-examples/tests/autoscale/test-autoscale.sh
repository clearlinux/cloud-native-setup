#!/bin/bash

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
kubectl apply -f $SCRIPT_DIR
watch kubectl describe hpa
