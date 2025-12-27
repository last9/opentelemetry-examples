# Google Cloud Run OpenTelemetry Integration

Send traces, logs, and metrics from Google Cloud Run to Last9 using OpenTelemetry.

## Overview

This directory contains examples for instrumenting Cloud Run services and jobs with OpenTelemetry, demonstrating multiple deployment patterns and language implementations.

## Deployment Patterns

### Pattern 1: Direct SDK Export (Recommended)
Application sends telemetry directly to Last9 via OTLP.

```
Cloud Run Service → OTLP → Last9
```

**Pros**: Simple, no extra containers, lower cost
**Cons**: Slightly higher cold start latency

### Pattern 2: Sidecar Collector
Application sends to a local OTEL Collector sidecar, which exports to Last9.

```
App Container → localhost:4318 → OTEL Collector Sidecar → Last9
```

**Pros**: Buffering, retries, batching handled by collector
**Cons**: Requires multi-container (beta), higher memory usage

### Pattern 3: Cloud Logging Integration
Logs flow through Cloud Logging, then to Last9 via Pub/Sub.

```
Cloud Run → Cloud Logging → Log Sink → Pub/Sub → OTEL Collector → Last9
```

**Pros**: Works with existing Cloud Logging setup, centralized log management
**Cons**: Higher latency, requires external collector

## Language Examples

| Language | Framework | Directory |
|----------|-----------|-----------|
| Python | Flask | [python/flask/](./python/flask/) |
| Node.js | Express | [nodejs/express/](./nodejs/express/) |
| Go | Gin | [go/gin/](./go/gin/) |
| Java | Spring Boot | [java/springboot/](./java/springboot/) |

## Collector Configurations

| Pattern | Directory |
|---------|-----------|
| Sidecar | [collector-configs/sidecar/](./collector-configs/sidecar/) |
| Cloud Logging | [collector-configs/cloud-logging/](./collector-configs/cloud-logging/) |

## Cloud Run Jobs

For batch processing workloads, see [jobs/](./jobs/).

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
echo -n "Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Grant Cloud Run access to the secret
gcloud secrets add-iam-policy-binding last9-auth-header \
  --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

## Environment Variables

All examples use these standard OTEL environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name for telemetry | `my-cloud-run-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint | `https://otlp.last9.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth header | `Authorization=Basic ...` |
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

## Structured Logging

For trace correlation in Cloud Logging, logs should include:

```json
{
  "severity": "INFO",
  "message": "Request processed",
  "logging.googleapis.com/trace": "projects/PROJECT_ID/traces/TRACE_ID",
  "logging.googleapis.com/spanId": "SPAN_ID"
}
```

All examples implement this pattern automatically.

## Quick Start

### 1. Choose an example

```bash
cd python/flask  # or nodejs/express, go/gin, java/springboot
```

### 2. Set environment variables

```bash
export PROJECT_ID=your-gcp-project
export REGION=us-central1
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"
```

### 3. Build and deploy

```bash
# Build with Cloud Build
gcloud builds submit --config cloudbuild.yaml

# Or deploy directly
gcloud run deploy SERVICE_NAME \
  --source . \
  --region $REGION \
  --set-env-vars "OTEL_SERVICE_NAME=my-service" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_EXPORTER_OTLP_ENDPOINT" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 4. Verify in Last9

1. Generate traffic to your Cloud Run service
2. Navigate to Last9 APM dashboard
3. Filter by your service name
4. View traces, logs, and metrics

## Troubleshooting

### Cold Start Timeouts

If spans are not appearing:
- Ensure graceful shutdown is implemented
- Increase `--timeout` for your Cloud Run service
- Use `BatchSpanProcessor` with reasonable timeout (5-10s)

### Memory Issues with Sidecar

- Minimum recommended: 512MB total (256MB app + 256MB collector)
- Use `memory_limiter` processor in collector config

### Authentication Errors

- Verify secret is accessible: `gcloud secrets versions access latest --secret=last9-auth-header`
- Check service account has `secretmanager.secretAccessor` role

### No Trace Correlation in Logs

- Ensure structured JSON logging is enabled
- Verify `logging.googleapis.com/trace` field format includes project ID

## Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Last9 Integration Guide](https://last9.io/docs/integrations-gcp-cloud-run/)
