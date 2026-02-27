# Monitoring Argo Rollouts with OpenTelemetry and Last9

Monitor Argo Rollouts canary deployments by scraping Prometheus metrics via the OpenTelemetry Collector and shipping them to Last9. This enables dashboards that track rollout phase, canary traffic weight, and pod-level canary vs stable comparisons.

## Prerequisites

- Kubernetes cluster with [Argo Rollouts installed](https://argo-rollouts.readthedocs.io/en/stable/installation/)
- `kubectl` configured with cluster access
- Last9 account — get your OTLP endpoint and auth header from the [Integrations page](https://app.last9.io/integrations)

Verify Argo Rollouts is running:

```bash
kubectl get deploy -n argo-rollouts
kubectl get svc -n argo-rollouts
```

The metrics service should be present on port `8090`:

```bash
kubectl get svc argo-rollouts-metrics -n argo-rollouts
```

## Quick Start

### 1. Deploy the OTel Collector

Edit `collector-deployment.yaml` and replace the placeholders:

| Placeholder | Value |
|---|---|
| `YOUR_LAST9_OTLP_ENDPOINT` | From Last9 Integrations page |
| `YOUR_LAST9_AUTH_HEADER` | From Last9 Integrations page |
| `YOUR_CLUSTER_NAME` | Your cluster identifier |

Apply the manifest:

```bash
kubectl apply -f collector-deployment.yaml
```

This creates the `monitoring` namespace, a ConfigMap with the OTel config, the Collector Deployment, and the RBAC resources needed for Prometheus scraping.

### 2. Verify the Collector is Running

```bash
kubectl get pods -n monitoring -l app=otel-collector
kubectl logs -n monitoring -l app=otel-collector --tail=50
```

Look for log lines showing successful scrape of `argo-rollouts` and metric export to Last9.

### 3. Confirm Metrics in Last9

Port-forward the Argo Rollouts metrics endpoint to verify it's reachable:

```bash
kubectl port-forward svc/argo-rollouts-metrics -n argo-rollouts 8090:8090
curl -s http://localhost:8090/metrics | grep -E "^rollout_info|^rollout_reconcile"
```

Then open [Metrics Explorer](https://app.last9.io/metrics) and search for `rollout_info`.

## Configuration

### Environment Variables

See `.env.example` for all required variables.

| Variable | Description |
|---|---|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP write endpoint |
| `LAST9_AUTH_HEADER` | Last9 authorization header |
| `K8S_CLUSTER_NAME` | Cluster label for multi-cluster dashboards |
| `DEPLOYMENT_ENVIRONMENT` | Environment label (`production`, `staging`, etc.) |

### Using `otel-config.yaml` with an Existing Collector

If you already have an OTel Collector running, copy the receiver and pipeline config from `otel-config.yaml` into your existing configuration instead of deploying a new one.

## Metrics Reference

| Metric | Description | Key Labels |
|---|---|---|
| `rollout_info` | Rollout status, phase, canary weight | `namespace`, `rollout`, `phase`, `canary_weight` |
| `rollout_reconcile` | Reconcile duration histogram | `namespace`, `rollout` |
| `rollout_reconcile_error` | Reconcile error count | `namespace`, `rollout` |
| `analysis_run_info` | Analysis run status | `namespace`, `rollout`, `phase` |
| `experiment_info` | Experiment status | `namespace`, `experiment` |
| `argo_rollouts_controller_workqueue_depth` | Controller queue backlog | `name` |

## Dashboard Attributes

| Attribute | Example | Use |
|---|---|---|
| `service.name` | `argo-rollouts` | Filter all rollout metrics |
| `k8s.cluster.name` | `prod-us-east-1` | Multi-cluster view |
| `deployment.environment` | `production` | Environment comparison |
| `namespace` | `payments` | Per-namespace health |
| `rollout` | `checkout-rollout` | Per-rollout panels |
| `canary_weight` | `0`–`100` | Canary traffic split |
| `phase` | `Progressing`, `Paused`, `Healthy`, `Degraded` | Rollout status |

<details>
<summary>Canary vs Stable Pod Metrics</summary>

To compare canary vs stable pods in dashboards, the collector config also scrapes `kube-state-metrics`. Argo Rollouts automatically labels pods with `rollouts-pod-template-hash` during progressive delivery.

Use `rollout_info{canary_weight="X"}` to see current traffic split, and filter pod metrics by `label_rollouts_pod_template_hash` to compare canary vs stable performance.

| Kubernetes Label | Description |
|---|---|
| `rollouts-pod-template-hash` | Distinguishes canary vs stable pod revision |
| `app` | Application name |

</details>

<details>
<summary>Suggested Dashboard Panels</summary>

1. **Canary Traffic Weight Over Time** — `rollout_info` grouped by `canary_weight`
2. **Rollout Phase Status** — `rollout_info` grouped by `phase` and `rollout`
3. **Reconcile Error Rate** — `rate(rollout_reconcile_error[5m])` grouped by `rollout`, `namespace`
4. **Analysis Run Success/Failure** — `analysis_run_info` grouped by `phase`, `rollout`
5. **Pod Count: Canary vs Stable** — `kube_pod_status_phase` filtered by `label_rollouts_pod_template_hash`

</details>

<details>
<summary>Troubleshooting</summary>

**Metrics endpoint not accessible:**
```bash
kubectl get svc -n argo-rollouts
kubectl logs -n argo-rollouts deploy/argo-rollouts
```

**Collector not scraping:**
```bash
kubectl logs -n monitoring -l app=otel-collector | grep -i error
```

**No data in Last9:**
1. Verify the OTLP endpoint and auth header are correct in the ConfigMap
2. Check that `compression: gzip` is supported by your Last9 endpoint
3. Remove the `debug` exporter if you want to reduce log verbosity

</details>
