# Cloud Run Infrastructure Metrics with OpenTelemetry Collector

Centralized OpenTelemetry Collector that pulls Google Cloud Run infrastructure metrics from Cloud Monitoring API and forwards them to Last9 via OTLP.

## What This Solves

Your Cloud Run applications emit **application telemetry** (traces, logs, custom metrics) directly to Last9. However, **GCP platform-level metrics** (instance count, billable time, etc.) are only available in Cloud Monitoring.

This OTEL Collector bridges that gap for basic infrastructure monitoring.

## Prerequisites

1. **GCP Project** with Cloud Run services deployed
2. **gcloud CLI** installed and authenticated
3. **Last9 Account** with OTLP credentials (same as your application)
4. **Secret Manager** to store Last9 credentials

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

**Get your credentials from Last9**:
1. Log in to Last9 console
2. Navigate to Settings → Integrations → OTLP
3. Copy the OTLP endpoint and authorization header

**Store in Secret Manager**:
```bash
# Store authorization header (same as your application uses)
# IMPORTANT: Include "Authorization=" prefix
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Verify secret
gcloud secrets versions access latest --secret=last9-auth-header
```

### Step 3: Deploy OTEL Collector

```bash
# Deploy using Cloud Build (recommended)
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=cloud-run-metrics-collector,_REGION=us-central1,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT

# Replace YOUR_OTLP_ENDPOINT with your Last9 OTLP endpoint
```

**Or deploy directly**:
```bash
# Build image
docker build -t gcr.io/YOUR_PROJECT_ID/cloud-run-metrics-collector .
docker push gcr.io/YOUR_PROJECT_ID/cloud-run-metrics-collector

# Deploy
gcloud run deploy cloud-run-metrics-collector \
  --image gcr.io/YOUR_PROJECT_ID/cloud-run-metrics-collector \
  --region us-central1 \
  --no-allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 1 \
  --max-instances 1 \
  --service-account metrics-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars GCP_PROJECT_ID=YOUR_PROJECT_ID \
  --set-env-vars OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT \
  --set-secrets OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest
```

### Step 4: Verify

1. **Check collector logs**:
```bash
gcloud run services logs read cloud-run-metrics-collector --region us-central1 --limit 50
```

Look for successful metric collection (check for "Unsupported distribution metric kind" warnings - these are expected).

2. **Check Last9 dashboard**:
   - You should see metrics with `run_googleapis_com_` prefix
   - Filter by `collector_type="gcp-infrastructure-metrics"`

3. **Query example metrics in Last9**:
```promql
# Instance count over time
run_googleapis_com_container_instance_count

# Billable time increase
increase(run_googleapis_com_container_billable_instance_time[5m])
```

## Configuration

### Customize Collection Interval

Edit `collector-config.yaml`:

```yaml
receivers:
  googlecloudmonitoring:
    collection_interval: 300s  # Change from 60s to 5 minutes
    # ... rest of config
```

**Warning**: Minimum recommended is 300s (5 minute) for infrastructure metrics to avoid excessive API calls.

### Filter by Specific Services

Edit `collector-config.yaml`:

```yaml
receivers:
  googlecloudmonitoring:
    # ... other config
    metrics_list:
      - metric_descriptor_filter: 'metric.type = starts_with("run.googleapis.com") AND resource.service_name = "my-service"'
```

## Resources

- [OTEL Collector Documentation](https://opentelemetry.io/docs/collector/)
- [googlecloudmonitoring Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/googlecloudmonitoringreceiver)
- [Cloud Run Metrics Reference](https://cloud.google.com/monitoring/api/metrics_gcp_p_z#gcp-run)
- [Cloud Monitoring API Quotas](https://cloud.google.com/monitoring/quotas)
