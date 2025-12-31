# Cloud Run Infrastructure Metrics with Grafana Alloy

Centralized Grafana Alloy collector that pulls Google Cloud Run infrastructure metrics from Cloud Monitoring API and forwards them to Last9 via Prometheus remote write.

## What This Solves

Your Cloud Run applications emit **application telemetry** (traces, logs, custom metrics) directly to Last9. However, **GCP platform-level metrics** (CPU, memory, instance count, cold starts, billable time) are only available in Cloud Monitoring.

This Grafana Alloy collector bridges that gap, providing complete observability.

## Why Grafana Alloy?

Grafana Alloy is the **recommended solution** for collecting GCP Cloud Run infrastructure metrics because:

| Feature | Grafana Alloy | OpenTelemetry Collector |
|---------|--------------|------------------------|
| **GCP Metrics Support** | ✅ Native support via `prometheus.exporter.gcp` | ⚠️ Limited - only basic gauge metrics |
| **Distribution Metrics** | ✅ Handles all GCP metric types | ❌ Cannot process Distribution (histogram) metrics |
| **Metric Filtering** | ✅ Simple prefix-based filtering | ⚠️ Complex metric-by-metric configuration |
| **Metrics Collected** | ✅ 10+ metrics (CPU, memory, latency, etc.) | ❌ 1-2 metrics (only instance_count) |
| **Protocol** | ✅ Prometheus Remote Write (native) | ⚠️ Requires conversion |

**What you'll miss with OTEL Collector**: CPU utilization, memory utilization, request latencies, startup latency, and more - all stored as Distribution metrics in GCP.

## Architecture

```
┌──────────────────────────────────────────────────┐
│          Your Cloud Run Services                 │
│  (Send app telemetry directly to Last9)          │
└──────────────────────────────────────────────────┘
                    │
                    ├─► OTLP → Last9
                    │   (traces, logs, custom metrics)
                    │
                    ▼
┌──────────────────────────────────────────────────┐
│         GCP Cloud Monitoring API                 │
│  (Automatically captures platform metrics)       │
│  - CPU/Memory usage                              │
│  - Instance count                                │
│  - Cold start latency                            │
│  - Billable time                                 │
│  - Request count & latency                       │
└──────────────────────────────────────────────────┘
                    │
                    │ Pull every 5 minutes
                    ▼
┌──────────────────────────────────────────────────┐
│     Grafana Alloy Collector (Cloud Run)          │
│  ┌────────────────────────────────────────────┐  │
│  │ prometheus.exporter.gcp                   │  │
│  │ (pulls metrics from Monitoring API)       │  │
│  └────────────────────────────────────────────┘  │
│                    │                              │
│                    ▼                              │
│  ┌────────────────────────────────────────────┐  │
│  │ prometheus.scrape                         │  │
│  └────────────────────────────────────────────┘  │
│                    │                              │
│                    ▼                              │
│  ┌────────────────────────────────────────────┐  │
│  │ prometheus.remote_write → Last9           │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────┐
│                  Last9                           │
│  (App metrics + Infrastructure metrics)          │
└──────────────────────────────────────────────────┘
```

## Metrics Collected

Grafana Alloy collects all Cloud Run infrastructure metrics as `stackdriver_*` metrics:

| Metric | Description | Use Case |
|--------|-------------|----------|
| `stackdriver_cloud_run_revision_run_googleapis_com_container_billable_instance_time` | Billable container seconds | **Cost tracking & optimization** |
| `stackdriver_cloud_run_revision_run_googleapis_com_container_instance_count` | Number of active instances | **Scaling pattern analysis** |
| `stackdriver_cloud_run_revision_run_googleapis_com_container_cpu_allocation_time` | CPU time allocated | **Resource utilization** |
| `stackdriver_cloud_run_revision_run_googleapis_com_container_cpu_utilizations` | CPU usage distribution (histogram) | **Performance tuning** |
| `stackdriver_cloud_run_revision_run_googleapis_com_container_memory_utilizations` | Memory usage distribution (histogram) | **Right-sizing instances** |
| `stackdriver_cloud_run_revision_run_googleapis_com_container_startup_latencies` | Container cold start time (histogram) | **Cold start optimization** |
| `stackdriver_cloud_run_revision_run_googleapis_com_request_count` | Platform-level request count | **Traffic validation** |
| `stackdriver_cloud_run_revision_run_googleapis_com_request_latencies` | Platform-measured latency (histogram) | **SLO tracking** |

**Query examples**:
```promql
# CPU utilization by service
rate(stackdriver_cloud_run_revision_run_googleapis_com_container_cpu_utilizations_sum[5m])

# Memory usage 95th percentile
histogram_quantile(0.95,
  rate(stackdriver_cloud_run_revision_run_googleapis_com_container_memory_utilizations_bucket[5m])
)

# Daily billable time (cost analysis)
sum(increase(stackdriver_cloud_run_revision_run_googleapis_com_container_billable_instance_time[1d]))
  by (service_name)
```

**Full GCP metric list**: https://cloud.google.com/monitoring/api/metrics_gcp_p_z (search for `run.googleapis.com`)

## Prerequisites

1. **GCP Project** with Cloud Run services deployed
2. **gcloud CLI** installed and authenticated
3. **Last9 Account** with Prometheus remote write credentials
4. **Secret Manager** with Last9 credentials stored

## Quick Start

### Step 1: Setup IAM

```bash
# Run the setup script to create service account with correct permissions
./setup-iam.sh YOUR_PROJECT_ID
```

This creates a service account `metrics-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com` with:
- `roles/monitoring.viewer` - Read Cloud Monitoring metrics
- `roles/secretmanager.secretAccessor` - Read Last9 credentials

### Step 2: Store Last9 Credentials

Grafana Alloy uses **Prometheus remote write** with basic authentication.

**Get your credentials from Last9**:
1. Log in to Last9 console
2. Navigate to Settings → Integrations → Prometheus
3. Copy the remote write URL, username, and password

**Store in Secret Manager**:
```bash
# Store username
echo -n "YOUR_LAST9_USERNAME" | \
  gcloud secrets create last9-username --data-file=-

# Store password
echo -n "YOUR_LAST9_PASSWORD" | \
  gcloud secrets create last9-password --data-file=-

# Verify secrets
gcloud secrets versions access latest --secret=last9-username
gcloud secrets versions access latest --secret=last9-password
```

### Step 3: Deploy Grafana Alloy

```bash
# Deploy using Cloud Build (recommended)
gcloud builds submit --config cloudbuild-alloy.yaml \
  --substitutions=_SERVICE_NAME=cloud-run-metrics-alloy,_REGION=us-central1,_REMOTE_WRITE_URL=YOUR_REMOTE_WRITE_URL

# Replace YOUR_REMOTE_WRITE_URL with your Last9 Prometheus remote write endpoint
# Example format: https://app-tsdb.last9.io/v1/metrics/WORKSPACE_ID/sender/last9/write
```

**Or deploy directly**:
```bash
# Build image
docker build -f Dockerfile.alloy -t gcr.io/YOUR_PROJECT_ID/cloud-run-metrics-alloy .
docker push gcr.io/YOUR_PROJECT_ID/cloud-run-metrics-alloy

# Deploy
gcloud run deploy cloud-run-metrics-alloy \
  --image gcr.io/YOUR_PROJECT_ID/cloud-run-metrics-alloy \
  --region us-central1 \
  --no-allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 1 \
  --max-instances 1 \
  --service-account metrics-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars GCP_PROJECT_ID=YOUR_PROJECT_ID \
  --set-env-vars LAST9_REMOTE_WRITE_URL=YOUR_REMOTE_WRITE_URL \
  --set-secrets LAST9_USERNAME=last9-username:latest \
  --set-secrets LAST9_PASSWORD=last9-password:latest
```

### Step 4: Verify

1. **Check Alloy logs**:
```bash
gcloud run services logs read cloud-run-metrics-alloy --region us-central1 --limit 50
```

Look for successful metric scrapes (no error messages about authentication or metric collection).

2. **Check Last9 dashboard**:
   - Filter by `source="grafana-alloy"` and `collector_type="gcp-infrastructure-metrics"`
   - You should see metrics with `stackdriver_cloud_run_revision_` prefix

3. **Query example metrics in Last9**:
```promql
# Instance count over time
stackdriver_cloud_run_revision_run_googleapis_com_container_instance_count

# CPU utilization rate
rate(stackdriver_cloud_run_revision_run_googleapis_com_container_cpu_utilizations_sum[5m])
```

## Configuration

### Customize Collection Interval

Edit `alloy-config.alloy`:

```alloy
prometheus.scrape "gcp_metrics" {
  targets    = prometheus.exporter.gcp.cloud_run.targets
  forward_to = [prometheus.remote_write.last9.receiver]

  scrape_interval = "10m"  // Change from 5m to 10 minutes for less frequent polling
}
```

**Warning**: Minimum recommended is 5m (5 minutes) for infrastructure metrics to avoid excessive API calls.

### Filter by Specific Services

Edit `alloy-config.alloy`:

```alloy
prometheus.exporter.gcp "cloud_run" {
  project_ids = [env("GCP_PROJECT_ID")]

  metrics_prefixes = [
    "run.googleapis.com",
  ]

  // Add filter for specific service
  extra_filters = [
    "resource.service_name=my-service-name",
  ]
}
```

### Adjust External Labels

Edit `alloy-config.alloy`:

```alloy
prometheus.remote_write "last9" {
  endpoint {
    url = env("LAST9_REMOTE_WRITE_URL")
    // ... other config ...
  }

  external_labels = {
    source = "grafana-alloy",
    environment = "production",  // Change to "staging", "dev", etc.
    collector_type = "gcp-infrastructure-metrics",
    region = "us-central1",  // Add custom labels
  }
}
```

## Cost Analysis

| Component | Configuration | Monthly Cost (Estimate) |
|-----------|---------------|------------------------|
| **Grafana Alloy (Cloud Run)** | 512Mi, 1 CPU, min=1 | ~$8-12 (always-on) |
| **Cloud Monitoring API** | ~288 requests/day @ 5m interval | Free (under quota) |
| **Secret Manager** | 2 secrets, ~288 accesses/day | Free tier |
| **Last9 Ingestion** | ~200-500 metric series | Check your plan |

**Cost Optimization**:
- ✅ Set `min-instances=1` - Collector needs to run continuously
- ✅ Use 5m scrape interval (default) - Good balance of freshness and API usage
- ⚠️ Don't set `min-instances=0` - Alloy must run continuously to collect time-series data

## Troubleshooting

### No Metrics in Last9

**Check Alloy logs**:
```bash
gcloud run services logs read cloud-run-metrics-alloy --region us-central1 --limit 100
```

**Common issues**:

1. **IAM permissions missing**:
   ```
   Error: Permission denied on resource project PROJECT_ID
   ```
   **Fix**: Run `./setup-iam.sh YOUR_PROJECT_ID` again

2. **Invalid Last9 credentials (401 Unauthorized)**:
   ```
   Error: 401 Unauthorized
   ```
   **Fix**: Verify secrets:
   ```bash
   gcloud secrets versions access latest --secret=last9-username
   gcloud secrets versions access latest --secret=last9-password
   ```

3. **Wrong project ID**:
   ```
   Error: Project not found
   ```
   **Fix**: Ensure `GCP_PROJECT_ID` env var matches your project:
   ```bash
   gcloud run services describe cloud-run-metrics-alloy --region us-central1 \
     --format 'yaml(spec.template.spec.containers[0].env)'
   ```

4. **Remote write endpoint error**:
   ```
   Error: connection refused
   ```
   **Fix**: Verify `LAST9_REMOTE_WRITE_URL` is correct (should be Prometheus remote write URL, not OTLP endpoint)

### High Memory Usage

**Symptom**: Alloy restarts with OOM errors

**Solution**: Tune queue configuration in `alloy-config.alloy`:
```alloy
prometheus.remote_write "last9" {
  endpoint {
    url = env("LAST9_REMOTE_WRITE_URL")

    queue_config {
      capacity = 5000  // Reduce from 10000
      max_samples_per_send = 1500  // Reduce from 3000
      // ... other config ...
    }
  }
}
```

### API Quota Exceeded

**Symptom**:
```
Error: Quota exceeded for quota metric 'Read requests' and limit 'Read requests per minute'
```

**Solution**: Increase scrape interval in `alloy-config.alloy`:
```alloy
prometheus.scrape "gcp_metrics" {
  scrape_interval = "10m"  // Increase from 5m to reduce API calls
}
```

### Only Seeing Alloy's Own Metrics

**Symptom**: Only see `alloy_*` metrics, no `stackdriver_*` metrics

**Possible causes**:
1. Service account doesn't have `monitoring.viewer` role
2. Wrong `GCP_PROJECT_ID` environment variable
3. No Cloud Run services in the project

**Fix**: Check service account permissions:
```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:metrics-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

## Correlation with Application Metrics

To see both app + infrastructure metrics together in Last9:

### Consistent Service Naming

Ensure your application uses the same service name that GCP assigns:

**In your app** (Node.js example):
```javascript
serviceName: process.env.OTEL_SERVICE_NAME || process.env.K_SERVICE
```

**In GCP**: This automatically sets `service_name` label in infrastructure metrics

### Compare App vs Platform Metrics

```promql
# App-level latency (measured by SDK)
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{service_name="my-service"}[5m])
)

# Platform-level latency (measured by GCP)
histogram_quantile(0.95,
  rate(stackdriver_cloud_run_revision_run_googleapis_com_request_latencies_bucket{service_name="my-service"}[5m])
)

# Compare: Is there a discrepancy?
```

If platform latency is higher than app latency, it indicates cold start overhead or infrastructure issues.

## Files

| File | Description |
|------|-------------|
| `alloy-config.alloy` | Grafana Alloy configuration (recommended) |
| `Dockerfile.alloy` | Dockerfile for Grafana Alloy |
| `cloudbuild-alloy.yaml` | Cloud Build config for Alloy deployment |
| `collector-config.yaml` | OTEL Collector config (legacy, not recommended) |
| `Dockerfile` | Dockerfile for OTEL Collector (legacy) |
| `cloudbuild.yaml` | Cloud Build for OTEL Collector (legacy) |
| `setup-iam.sh` | IAM service account setup script |

## Resources

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [prometheus.exporter.gcp Reference](https://grafana.com/docs/alloy/latest/reference/components/prometheus.exporter.gcp/)
- [Cloud Run Metrics Reference](https://cloud.google.com/monitoring/api/metrics_gcp_p_z)
- [Cloud Monitoring API Quotas](https://cloud.google.com/monitoring/quotas)
