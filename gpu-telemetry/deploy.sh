#!/usr/bin/env bash
# One-shot deploy of l9gpu to a Kubernetes cluster, wired to Last9 OTLP.
#
# Required env:
#   LAST9_OTLP_ENDPOINT  e.g. otlp.last9.io:443
#   LAST9_AUTH_HEADER    e.g. "Basic <base64>"  (from app.last9.io integrations)
#   CLUSTER_NAME         e.g. prod-gpu-us-east

set -euo pipefail

: "${LAST9_OTLP_ENDPOINT:?set LAST9_OTLP_ENDPOINT}"
: "${LAST9_AUTH_HEADER:?set LAST9_AUTH_HEADER}"
: "${CLUSTER_NAME:?set CLUSTER_NAME}"

NAMESPACE="${NAMESPACE:-l9gpu}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic l9gpu-otlp \
  --from-literal=OTEL_EXPORTER_OTLP_ENDPOINT="$LAST9_OTLP_ENDPOINT" \
  --from-literal=OTEL_EXPORTER_OTLP_HEADERS="Authorization=$LAST9_AUTH_HEADER" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add l9gpu https://last9.github.io/gpu-telemetry >/dev/null 2>&1 || true
helm repo update l9gpu

helm upgrade --install l9gpu l9gpu/l9gpu \
  --namespace "$NAMESPACE" \
  --values values.yaml \
  --set monitoring.cluster="$CLUSTER_NAME"

echo
echo "Deployed. Check pods:"
echo "  kubectl -n $NAMESPACE get pods"
echo
echo "Verify metrics in Last9 (~1 min):"
echo "  https://app.last9.io/metrics?q=gpu_utilization"
