# OpenTelemetry GCP Cloud Functions & Cloud Run Chain Example

This example demonstrates how to instrument a chain of GCP services (Cloud Functions + Cloud Run) with OpenTelemetry for distributed tracing.

## Architecture

The services form a chain: `Service A → Service B → Service C`

- **Service A**: GCP Cloud Function (2nd gen) - Entry point
- **Service B**: GCP Cloud Run - Middle service
- **Service C**: GCP Cloud Run - Final service

## Key Features

- ✅ Full OpenTelemetry instrumentation with auto-instrumentation
- ✅ Custom trace context propagation for GCP (handles GCP's header modifications)
- ✅ Proper service dependency mapping
- ✅ Metrics, traces, and logs export via OTLP
- ✅ Local testing support
- ✅ Production-ready for GCP deployment

## Project Structure

```
gcp/cloud-functions-chain/
├── service-a/           # Cloud Function (Entry point)
│   ├── index.js
│   ├── tracing.js
│   └── package.json
├── service-b/           # Cloud Run (Middle)
│   ├── index.js
│   ├── tracing.js
│   └── package.json
├── service-c/           # Cloud Run (Final)
│   ├── index.js
│   ├── tracing.js
│   └── package.json
├── Dockerfile.function  # For Service A
├── Dockerfile.cloudrun  # For Service B & C
└── README.md
```

## Prerequisites

- Node.js 18 or higher
- GCP account with billing enabled (for deployment)
- OTLP-compatible observability backend

## Environment Variables

Each service requires the following environment variables:

```bash
# OpenTelemetry Configuration
OTEL_SERVICE_NAME="<service-name>"
OTEL_EXPORTER_OTLP_ENDPOINT="<your-otlp-endpoint>"
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-credentials>"
OTEL_TRACES_SAMPLER="always_on"
OTEL_RESOURCE_ATTRIBUTES="deployment.environment=<environment>"
OTEL_LOG_LEVEL=error

# Service URLs (for service-to-service communication)
SERVICE_B_URL="<service-b-url>"  # For Service A
SERVICE_C_URL="<service-c-url>"  # For Service B
```

## Local Testing

### 1. Install Dependencies

```bash
cd service-a && npm install
cd ../service-b && npm install
cd ../service-c && npm install
```

### 2. Start Services

Start services in order (C → B → A):

**Service C:**
```bash
cd service-c
PORT=8083 \
OTEL_SERVICE_NAME="service-c" \
OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318" \
OTEL_TRACES_SAMPLER="always_on" \
OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local" \
node index.js
```

**Service B:**
```bash
cd service-b
PORT=8082 \
OTEL_SERVICE_NAME="service-b" \
OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318" \
OTEL_TRACES_SAMPLER="always_on" \
OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local" \
SERVICE_C_URL=http://localhost:8083 \
node index.js
```

**Service A:**
```bash
cd service-a
PORT=8081 \
OTEL_SERVICE_NAME="service-a" \
OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318" \
OTEL_TRACES_SAMPLER="always_on" \
OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local" \
SERVICE_B_URL=http://localhost:8082 \
FUNCTION_TARGET=startFlow \
npx @google-cloud/functions-framework --target=startFlow --port=8081
```

### 3. Test the Chain

```bash
# Test complete chain
curl -X POST http://localhost:8081/
```

Expected response:
```json
{
  "service": "service-a",
  "message": "Chain completed successfully",
  "chain": "A -> ...",
  "timestamp": "..."
}
```

## GCP Deployment

### Deploy in Order (C → B → A)

**1. Deploy Service C:**
```bash
cd service-c
gcloud run deploy service-c \
  --source . \
  --region=asia-south1 \
  --platform=managed \
  --allow-unauthenticated \
  --set-env-vars "OTEL_SERVICE_NAME=service-c,OTEL_EXPORTER_OTLP_ENDPOINT=<endpoint>,OTEL_EXPORTER_OTLP_HEADERS=<credentials>"
```

**2. Deploy Service B:**
```bash
cd service-b
gcloud run deploy service-b \
  --source . \
  --region=asia-south1 \
  --platform=managed \
  --allow-unauthenticated \
  --set-env-vars "OTEL_SERVICE_NAME=service-b,OTEL_EXPORTER_OTLP_ENDPOINT=<endpoint>,OTEL_EXPORTER_OTLP_HEADERS=<credentials>,SERVICE_C_URL=<service-c-url>"
```

**3. Deploy Service A:**
```bash
cd service-a
gcloud functions deploy startFlow \
  --gen2 \
  --runtime=nodejs20 \
  --region=asia-south1 \
  --source=. \
  --entry-point=startFlow \
  --trigger-http \
  --allow-unauthenticated \
  --set-env-vars "OTEL_SERVICE_NAME=service-a,OTEL_EXPORTER_OTLP_ENDPOINT=<endpoint>,OTEL_EXPORTER_OTLP_HEADERS=<credentials>,SERVICE_B_URL=<service-b-url>"
```

## Key Implementation Details

### Custom Trace Propagation

GCP's load balancers modify the standard `traceparent` header, which can break trace context. This implementation includes a custom `CloudRunTracePropagator` that:

1. Injects both standard (`traceparent`) and backup (`x-original-traceparent`) headers
2. Extracts from backup headers first (unmodified by GCP)
3. Falls back to standard headers if backup not found

This ensures proper parent-child relationships in distributed traces.

### Auto-Instrumentation

The setup uses OpenTelemetry auto-instrumentation for:
- HTTP/HTTPS (axios, node:http, node:https)
- Express.js
- Other common Node.js libraries

No manual instrumentation required - traces are created automatically.

## Troubleshooting

### Traces Not Appearing

1. Check OTLP endpoint connectivity
2. Verify authentication headers
3. Check service logs for errors

### Broken Trace Chains

1. Verify trace context propagation in logs
2. Check for same trace ID across services
3. Ensure custom propagator is active

### Service Communication Errors

1. Verify service URLs are correct
2. Check network connectivity
3. Ensure services allow incoming requests

## License

MIT
