# Cloud Run Service with OpenTelemetry

Node.js Express service with OpenTelemetry auto-instrumentation for distributed tracing.

## Prerequisites

- Google Cloud CLI (`gcloud`)
- Docker
- Node.js 18+

## Quick Start

### 1. Deploy to Cloud Run

```bash
# Set your project
export PROJECT_ID=your-project-id
export REGION=europe-west1

# Build and deploy
gcloud run deploy cloud-run-service-otel \
  --source . \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io" \
  --set-env-vars="OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your-credentials>" \
  --set-env-vars="OTEL_SERVICE_NAME=cloud-run-service" \
  --set-env-vars="FUNCTION_URL=https://your-function.run.app"
```

### 2. Test the service

```bash
# Health check
curl https://your-service-url.run.app/health

# Process endpoint
curl https://your-service-url.run.app/process?foo=bar

# Chain call (calls the function, propagates trace context)
curl https://your-service-url.run.app/chain?name=Test
```

## Configuration

| Variable | Description |
|----------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint (e.g., `https://otlp.last9.io`) |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers (e.g., `Authorization=Basic xxx`) |
| `OTEL_SERVICE_NAME` | Service name in traces |
| `FUNCTION_URL` | URL of Cloud Run Function for chain calls |

## Verification

Check Last9 dashboard for traces showing:
- `cloud-run-service` spans
- Child spans for HTTP calls to the function
- Connected trace IDs across services
