# Google Cloud Run OpenTelemetry Integration

Complete observability for Google Cloud Run with traces, logs, and metrics sent to Last9 using OpenTelemetry.

## Overview

This directory contains examples for instrumenting Cloud Run services with OpenTelemetry, providing **complete observability** through:

### 1. Application Telemetry (via OTLP SDK)
Deploy your application with OpenTelemetry instrumentation to send:
- **Distributed traces** - Request flows across services
- **Structured logs** - With automatic trace correlation
- **Custom application metrics** - Business KPIs, counters, histograms
- **HTTP instrumentation** - Automatic request/response tracking

**Choose your language**: [Node.js](#language-examples) | [Python](#language-examples) | [Go](#language-examples)

### 2. Infrastructure Metrics (via Grafana Alloy)
Deploy a centralized Grafana Alloy collector to pull GCP platform metrics:
- **CPU & memory utilization** - Distribution histograms for performance tuning
- **Instance count** - Scaling patterns and autoscaling behavior
- **Request latency** - Platform-measured (compare with app-measured)
- **Billable time** - Cost tracking and optimization
- **Network traffic** - Ingress/egress for cost analysis
- **Cold start latency** - Container startup time distribution

**Setup guide**: [Infrastructure Metrics](#infrastructure-metrics-setup)

## Complete Observability = Both Parts

**IMPORTANT**: To achieve complete observability, you need to deploy BOTH:

1. **Your application** (with OTLP SDK) → Sends app telemetry to Last9
2. **Grafana Alloy collector** → Pulls GCP infrastructure metrics to Last9

```
┌─────────────────────────────────────┐
│   Your Cloud Run Application        │
│   (Node.js/Python/Go + OTLP SDK)   │
│                                     │
│   Traces, Logs, Custom Metrics      │
└──────────────────┬──────────────────┘
                   │
                   ├─► OTLP → Last9
                   │
                   ▼
┌─────────────────────────────────────┐
│   GCP Cloud Monitoring API          │
│   (Platform Metrics - automatic)    │
└──────────────────┬──────────────────┘
                   │
                   │ Pull every 5 minutes
                   ▼
┌─────────────────────────────────────┐
│   Grafana Alloy Collector           │
│   (Deployed as Cloud Run service)   │
│                                     │
│   Prometheus Remote Write           │
└──────────────────┬──────────────────┘
                   │
                   ├─► Last9
                   │
                   ▼
┌─────────────────────────────────────┐
│        Last9 Platform               │
│                                     │
│  Complete Observability Dashboard   │
│  - App Telemetry                    │
│  - Infrastructure Metrics           │
└─────────────────────────────────────┘
```

## How It Works

This integration uses **direct OTLP export** - the simplest and most efficient approach:

```
┌────────────────────────────────────────┐
│  Your Cloud Run Application            │
│  (instrumented with OTLP SDK)          │
│                                        │
│  • Traces                              │
│  • Logs (with trace correlation)       │
│  • Custom Metrics                      │
└───────────────┬────────────────────────┘
                │
                │ OTLP/HTTP
                │ (direct export)
                ▼
        ┌──────────────┐
        │    Last9     │
        └──────────────┘
```

**Benefits**:
- ✅ Simple - No sidecars or additional infrastructure
- ✅ Low latency - Direct export to Last9
- ✅ Cost-effective - No extra containers
- ✅ Reliable - Built-in batching and retries in SDK

## Language Examples

| Language | Framework | Directory |
|----------|-----------|-----------|
| Python | Flask | [python/flask/](./python/flask/) |
| Node.js | Express | [nodejs/express/](./nodejs/express/) |
| Go | Gin | [go/gin/](./go/gin/) |
| Python | Batch Job | [python/job/](./python/job/) |

## Cloud Run Jobs

For batch processing workloads (ETL, data processing, scheduled tasks), see [python/job/](./python/job/).

## Prerequisites

1. **GCP Project** with Cloud Run API enabled
2. **gcloud CLI** installed and configured
3. **Last9 Account** with OTLP credentials
4. **Docker** (for local testing)

### Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com
```

### Store Last9 Credentials in Secret Manager

```bash
# Create secret for Last9 auth header
# IMPORTANT: Include "Authorization=" prefix in the secret value
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Verify secret was created correctly
gcloud secrets versions access latest --secret=last9-auth-header

# Grant Cloud Run access to the secret
gcloud secrets add-iam-policy-binding last9-auth-header \
  --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Finding your Last9 credentials:**
1. Log in to Last9 console
2. Navigate to Settings → Integrations → OTLP
3. Copy the base64-encoded credentials
4. Format as: `Authorization=Basic <base64_credentials>`

## Environment Variables

All examples use these standard OTEL environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name for telemetry | `my-cloud-run-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint (region-specific) | `YOUR_OTLP_ENDPOINT` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth header (from Secret Manager) | `Authorization=Basic ...` |
| `OTEL_TRACES_SAMPLER` | Sampling strategy | `always_on` |
| `OTEL_RESOURCE_ATTRIBUTES` | Additional attributes | `deployment.environment=prod` |

## Cloud Run Resource Attributes

The examples automatically detect and set these resource attributes:

| Attribute | Source | Description |
|-----------|--------|-------------|
| `cloud.provider` | hardcoded | `gcp` |
| `cloud.platform` | hardcoded | `gcp_cloud_run_revision` |
| `cloud.region` | `CLOUD_RUN_REGION` env | Region where service runs |
| `cloud.account.id` | `GOOGLE_CLOUD_PROJECT` env | GCP project ID |
| `service.instance.id` | `K_REVISION` env | Cloud Run revision name |
| `faas.name` | `K_SERVICE` env | Cloud Run service name |
| `faas.version` | `K_REVISION` env | Revision identifier |

## Telemetry Signals

### 1. Traces
All HTTP requests are automatically instrumented with distributed tracing. The examples capture:
- HTTP server spans (method, route, status code)
- Database query spans (when applicable)
- Custom business logic spans
- Error tracking and exceptions

### 2. Logs
Logs are exported in two ways:
- **OTLP Logs to Last9**: Structured logs with automatic trace correlation
- **Cloud Logging**: JSON logs for GCP console viewing

Log format with trace correlation:
```json
{
  "severity": "INFO",
  "message": "Request processed",
  "traceId": "abcd1234...",
  "spanId": "5678efgh...",
  "logging.googleapis.com/trace": "projects/PROJECT_ID/traces/TRACE_ID",
  "logging.googleapis.com/spanId": "SPAN_ID"
}
```

### 3. Metrics
Two types of metrics are collected:

**Application Metrics** (via SDK):
- HTTP request count and duration
- Custom business metrics
- Runtime metrics (memory, GC)

**Infrastructure Metrics** (via Grafana Alloy):
- CPU/memory utilization
- Instance count and scaling
- Request latency (platform-measured)
- Network traffic
- Billable time

See [Infrastructure Metrics Setup](#infrastructure-metrics-setup) below.

## Quick Start - Deploy Complete Observability in 4 Steps

### Step 1: Enable GCP APIs

```bash
export PROJECT_ID=your-gcp-project
gcloud config set project $PROJECT_ID

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com
```

### Step 2: Store Last9 Credentials

**Get your credentials from Last9**:
- **OTLP endpoint** and **authorization credentials** (for app telemetry)
- **Prometheus remote write URL**, **username**, and **password** (for infrastructure metrics)

**Store in Secret Manager**:
```bash
# For application telemetry (OTLP)
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# For infrastructure metrics (Prometheus remote write)
echo -n "YOUR_LAST9_USERNAME" | \
  gcloud secrets create last9-username --data-file=-

echo -n "YOUR_LAST9_PASSWORD" | \
  gcloud secrets create last9-password --data-file=-
```

### Step 3: Deploy Your Application with OpenTelemetry

Choose your language and follow the specific README:

**Node.js (Express)**:
```bash
cd nodejs/express
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=my-nodejs-service,_REGION=us-central1,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
```
📖 [Full Node.js guide](./nodejs/express/README.md)

**Python (Flask)**:
```bash
cd python/flask
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=my-flask-service,_REGION=us-central1,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
```
📖 [Full Python guide](./python/flask/README.md)

**Go (Gin)**:
```bash
cd go/gin
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=my-go-service,_REGION=us-central1,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
```
📖 [Full Go guide](./go/gin/README.md)

**Cloud Run Job (Python)**:
```bash
cd python/job
gcloud run jobs deploy my-batch-job \
  --source . \
  --region us-central1 \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```
📖 [Full Job guide](./python/job/README.md)

### Step 4: Deploy Grafana Alloy for Infrastructure Metrics

```bash
cd collector-configs/infrastructure-metrics

# Setup IAM service account
./setup-iam.sh $PROJECT_ID

# Deploy Grafana Alloy
gcloud builds submit --config cloudbuild-alloy.yaml \
  --substitutions=_SERVICE_NAME=cloud-run-metrics-alloy,_REGION=us-central1,_REMOTE_WRITE_URL=YOUR_REMOTE_WRITE_URL
```

📖 [Full infrastructure metrics guide](./collector-configs/infrastructure-metrics/README.md)

### Verify Complete Observability in Last9

1. **Generate traffic** to your Cloud Run service
2. **Navigate to Last9** dashboard
3. **Check Application Telemetry**:
   - Traces: APM → Traces → Filter by service name
   - Logs: Logs → Filter by `service.name="your-service"`
   - Metrics: Custom app metrics like `http_requests_total`
4. **Check Infrastructure Metrics**:
   - Filter by `source="grafana-alloy"`
   - Look for `stackdriver_cloud_run_revision_*` metrics
   - CPU, memory, instance count, latency distributions

## Troubleshooting

### Cold Start Timeouts

If spans are not appearing:
- Ensure graceful shutdown is implemented
- Increase `--timeout` for your Cloud Run service
- Use `BatchSpanProcessor` with reasonable timeout (5-10s)

### Authentication Errors

- Verify secret is accessible: `gcloud secrets versions access latest --secret=last9-auth-header`
- Check service account has `secretmanager.secretAccessor` role

### No Trace Correlation in Logs

- Ensure structured JSON logging is enabled
- Verify `logging.googleapis.com/trace` field format includes project ID

## Security Best Practices

### Secret Management

**✅ DO**: Use Secret Manager for credentials
```bash
# Create secret
echo -n "Authorization=Basic YOUR_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Grant access
gcloud secrets add-iam-policy-binding last9-auth-header \
  --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**❌ DON'T**: Store credentials in environment variables or code

### Secret Rotation

Rotate credentials using versioned secrets:
```bash
# Create new version
echo -n "Authorization=Basic NEW_CREDENTIALS" | \
  gcloud secrets versions add last9-auth-header --data-file=-

# Update service to use specific version
gcloud run services update SERVICE_NAME \
  --update-secrets OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:2
```

### IAM Least Privilege

Create dedicated service account per service:
```bash
# Create service account
gcloud iam service-accounts create my-cloud-run-service

# Grant minimal permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:my-cloud-run-service@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Deploy with service account
gcloud run deploy SERVICE_NAME \
  --service-account=my-cloud-run-service@PROJECT_ID.iam.gserviceaccount.com
```

### Recommended IAM Roles

| Role | Purpose | Assign To |
|------|---------|-----------|
| `roles/secretmanager.secretAccessor` | Read secrets | Service Account |
| `roles/monitoring.metricWriter` | Write custom metrics | Service Account |
| `roles/cloudtrace.agent` | Write traces | Service Account |
| `roles/logging.logWriter` | Write logs | Service Account (default) |

### Container Security

Scan images before deployment:
```bash
# Enable Container Scanning API
gcloud services enable containerscanning.googleapis.com

# Scan image
gcloud artifacts docker images scan gcr.io/PROJECT_ID/SERVICE_NAME:TAG

# View vulnerabilities
gcloud artifacts docker images list-vulnerabilities \
  gcr.io/PROJECT_ID/SERVICE_NAME:TAG
```

### Network Security

**Private services** (internal only):
```bash
gcloud run deploy SERVICE_NAME \
  --ingress=internal  # No public access
```

**VPC Connector** (access private resources):
```bash
gcloud run services update SERVICE_NAME \
  --vpc-connector=my-connector \
  --vpc-egress=private-ranges-only
```

## Infrastructure Metrics Setup

While your application sends traces, logs, and custom metrics via the OpenTelemetry SDK, **GCP platform-level metrics** (CPU, memory, instance count, etc.) are only available in Cloud Monitoring.

Deploy a centralized **Grafana Alloy collector** to pull these metrics and forward to Last9.

**Why Grafana Alloy?** Unlike OpenTelemetry Collector, Grafana Alloy natively supports all GCP metric types including Distribution (histogram) metrics. This means you'll get CPU utilization, memory utilization, request latency distributions, and more - not just simple gauge metrics like instance count.

### Why Infrastructure Metrics Matter

| Metric | Use Case |
|--------|----------|
| CPU/Memory Utilization | Right-size instances, detect resource issues |
| Instance Count | Track scaling patterns, optimize min/max instances |
| Request Latency (platform) | Compare with app-measured latency, detect platform issues |
| Billable Time | Cost tracking and optimization |
| Network Traffic | Monitor egress costs, detect anomalies |

### Quick Setup

**Full documentation**: [collector-configs/infrastructure-metrics/README.md](./collector-configs/infrastructure-metrics/README.md)

```bash
# 1. Create IAM service account
cd collector-configs/infrastructure-metrics
./setup-iam.sh YOUR_PROJECT_ID

# 2. Store Last9 credentials
echo -n "YOUR_LAST9_USERNAME" | \
  gcloud secrets create last9-username --data-file=-

echo -n "YOUR_LAST9_PASSWORD" | \
  gcloud secrets create last9-password --data-file=-

# 3. Deploy Grafana Alloy to Cloud Run
gcloud builds submit --config cloudbuild-alloy.yaml \
  --substitutions=_REMOTE_WRITE_URL=YOUR_REMOTE_WRITE_URL \
  --project=YOUR_PROJECT_ID

# Replace YOUR_REMOTE_WRITE_URL with your Last9 Prometheus remote write endpoint
# Example format: https://app-tsdb.last9.io/v1/metrics/WORKSPACE_ID/sender/last9/write

# 4. Verify metrics in Last9
# Filter by: source="grafana-alloy", collector_type="gcp-infrastructure-metrics"
```

The Grafana Alloy collector runs as a Cloud Run service with `min-instances=1` to continuously collect metrics every 5 minutes (configurable).

### What You'll See in Last9

Infrastructure metrics appear with the `stackdriver_` prefix:

```promql
# CPU utilization by service
rate(stackdriver_cloud_run_revision_run_googleapis_com_container_cpu_utilizations_sum[5m])

# Memory usage 95th percentile
histogram_quantile(0.95,
  rate(stackdriver_cloud_run_revision_run_googleapis_com_container_memory_utilizations_bucket[5m])
)

# Instance count over time
stackdriver_cloud_run_revision_run_googleapis_com_container_instance_count

# Daily billable time (cost analysis)
sum(increase(stackdriver_cloud_run_revision_run_googleapis_com_container_billable_instance_time[1d]))
  by (service_name)
```

### Architecture

```
┌─────────────────────────────┐
│   Your Cloud Run Services   │
│                              │
│  App Metrics/Traces/Logs     │
│         │                    │
│         ├─► OTLP → Last9     │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   GCP Cloud Monitoring API   │
│  (Platform Metrics)          │
└─────────────────────────────┘
         │
         │ Pull every 5 minutes
         ▼
┌─────────────────────────────┐
│   Grafana Alloy Collector   │
│   (Cloud Run Service)        │
│                              │
│   Prometheus Remote Write    │
│         │                    │
│         ├─► Last9            │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│        Last9 Platform        │
│                              │
│  App + Infrastructure Data   │
└─────────────────────────────┘
```

## Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Last9 Integration Guide](https://docs.last9.io)
