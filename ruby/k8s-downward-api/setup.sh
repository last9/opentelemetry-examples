#!/usr/bin/env bash
set -euo pipefail

CLUSTER=kind-local
IMAGE=ruby-k8s-demo:latest

command -v kind >/dev/null || { echo "install kind: brew install kind"; exit 1; }
command -v kubectl >/dev/null || { echo "install kubectl: brew install kubectl"; exit 1; }

if ! kind get clusters | grep -q "^${CLUSTER}$"; then
  kind create cluster --name "${CLUSTER}"
fi

docker build -t "${IMAGE}" .
kind load docker-image "${IMAGE}" --name "${CLUSTER}"

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/collector.yaml
kubectl apply -f k8s/deployment.yaml

kubectl -n demo rollout status deploy/otel-collector --timeout=120s
kubectl -n demo rollout status deploy/ruby-k8s-demo --timeout=120s

echo
echo "Port-forward app:  kubectl -n demo port-forward svc/ruby-k8s-demo 4567:4567"
echo "Curl:              curl localhost:4567/hello"
echo "Collector logs:    kubectl -n demo logs -l app=otel-collector -f"
