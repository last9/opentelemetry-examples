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
| `rollout_info` | Rollout presence and current phase | `name`, `namespace`, `phase`, `strategy` |
| `rollout_phase` | Phase gauge — one series per phase, value is 0 or 1 | `name`, `namespace`, `phase`, `strategy` |
| `rollout_info_replicas_available` | Available replica count | `name`, `namespace` |
| `rollout_info_replicas_updated` | Updated (canary) replica count | `name`, `namespace` |
| `rollout_reconcile` | Reconcile duration histogram | `name`, `namespace` |
| `rollout_reconcile_error` | Reconcile error count | `name`, `namespace` |
| `rollout_events_total` | Rollout lifecycle events | `name`, `namespace`, `reason`, `type` |
| `analysis_run_info` | Analysis run status | `name`, `namespace`, `phase` |
| `experiment_info` | Experiment status | `name`, `namespace` |
| `argo_rollouts_controller_workqueue_depth` | Controller queue backlog | `name` |

> **Note on canary traffic percentage:** Current Argo Rollouts versions do not expose `canary_weight` as a metric label. Track the canary replica fraction via `rollout_info_replicas_updated / rollout_info_replicas_desired`.

## Automated Canary Analysis with Last9

Beyond dashboards, Last9's Prometheus-compatible endpoint can act as an **automated canary gate** — Argo Rollouts queries your metrics at each rollout step and promotes or rolls back automatically.

### 1. Create the credentials Secret

Get your Prometheus username and password from the [Last9 Integrations page](https://app.last9.io/integrations) (Prometheus section).

> **Note:** The Argo Rollouts Prometheus provider does not support `basic_auth` natively. Pass credentials as a pre-encoded `Authorization` header stored in a K8s Secret:

```bash
kubectl create secret generic last9-prometheus-auth \
  --namespace <your-app-namespace> \
  --from-literal=authorization="Basic $(printf '<your-last9-username>:<your-last9-password>' | base64 | tr -d '\n')"
```

> Use `printf` and `tr -d '\n'` to avoid trailing newlines in the base64 output, which cause `invalid header field value` errors at runtime.

### 2. Apply the AnalysisTemplates

Edit `analysis-template.yaml` and replace `<your-last9-prometheus-read-endpoint>` with the full read URL from the Last9 Integrations page (Prometheus section):

```bash
kubectl apply -f analysis-template.yaml
```

This creates two templates:
- **`last9-http-error-rate`** — rolls back if HTTP 5xx error rate ≥ 10%, promotes if < 5%
- **`last9-latency-p99`** — rolls back if p99 latency ≥ 1s, promotes if < 500ms

### 3. Reference them in your Rollout

`rollout-example.yaml` shows how to wire both templates into a canary rollout with 10% → 25% → 50% → 100% steps. Apply and adapt it:

```bash
kubectl apply -f rollout-example.yaml
```

Watch analysis runs live:

```bash
kubectl argo rollouts get rollout my-app --watch
kubectl argo rollouts list analysisruns
```

### How it works

```
Canary at 10% traffic
      ↓
Argo Rollouts queries Last9 every 2 min
      ↓
error rate < 5%?  →  promote to 25%
error rate ≥ 10%? →  auto rollback (after 3 failures)
```

> **Note:** Your application must emit `http_requests_total` and `http_request_duration_seconds_bucket` metrics (standard Prometheus HTTP metrics). If you use different metric names, update the PromQL in `analysis-template.yaml`.

## Dashboard Attributes

| Attribute | Example | Use |
|---|---|---|
| `service.name` | `argo-rollouts` | Filter all rollout metrics |
| `k8s.cluster.name` | `prod-us-east-1` | Multi-cluster view |
| `deployment.environment` | `production` | Environment comparison |
| `namespace` | `payments` | Per-namespace health |
| `name` | `checkout-rollout` | Per-rollout panels |
| `phase` | `Progressing`, `Paused`, `Completed`, `Error` | Rollout status via `rollout_phase` |

<details>
<summary>Canary vs Stable Pod Metrics</summary>

To compare canary vs stable pods in dashboards, the collector config also scrapes `kube-state-metrics`. Argo Rollouts automatically labels pods with `rollouts-pod-template-hash` during progressive delivery.

Use `rollout_info_replicas_updated / rollout_info_replicas_desired` to see the current canary replica fraction, and filter pod metrics by `label_rollouts_pod_template_hash` to compare canary vs stable performance.

| Kubernetes Label | Description |
|---|---|
| `rollouts-pod-template-hash` | Distinguishes canary vs stable pod revision |
| `app` | Application name |

</details>

<details>
<summary>Suggested Dashboard Panels</summary>

1. **Canary Replica Fraction** — `rollout_info_replicas_updated / rollout_info_replicas_desired` grouped by `name`
2. **Rollout Phase Status** — `rollout_phase{phase="Progressing"}` or `rollout_phase` grouped by `phase` and `name`
3. **Reconcile Error Rate** — `rate(rollout_reconcile_error[5m])` grouped by `name`, `namespace`
4. **Analysis Run Success/Failure** — `analysis_run_info` grouped by `phase`, `name`
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
