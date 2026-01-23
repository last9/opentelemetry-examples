# Instrumenting Cloud Run Functions (2nd Gen) with OpenTelemetry

This example demonstrates how to integrate OpenTelemetry with Google Cloud Run Functions (2nd generation). The implementation includes HTTP-triggered functions and event-triggered functions (Pub/Sub, Cloud Storage) with automatic instrumentation, custom spans, and structured logging.

## Prerequisites

- Node.js 18+
- Google Cloud SDK (`gcloud`)
- [Last9](https://app.last9.io) account with OTLP credentials

## Quick Start

### Local Development

1. Install dependencies:

```bash
npm install
```

2. Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
# Edit .env with your OTLP endpoint and credentials
```

3. Run the HTTP function locally:

```bash
# Run helloHttp function
FUNCTION_TARGET=helloHttp npm start

# Or run processData function
FUNCTION_TARGET=processData npm start
```

4. Test the function:

```bash
# Hello function
curl "http://localhost:8080?name=Developer"

# Process data function
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"key": "value", "items": [1, 2, 3]}'
```

### Deploy to Google Cloud

**Step 1: Create the Last9 auth secret (one-time setup)**

```bash
# Include "Authorization=" prefix
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Grant the function's service account access to the secret
gcloud secrets add-iam-policy-binding last9-auth-header \
  --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Step 2: Deploy HTTP function**

```bash
gcloud functions deploy helloHttp \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=. \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --memory=256Mi \
  --set-env-vars="OTEL_SERVICE_NAME=hello-function" \
  --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

**Step 3: Deploy Pub/Sub triggered function (optional)**

```bash
# Create topic first
gcloud pubsub topics create my-topic

# Deploy function
gcloud functions deploy handlePubSub \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=. \
  --entry-point=handlePubSub \
  --trigger-topic=my-topic \
  --memory=256Mi \
  --set-env-vars="OTEL_SERVICE_NAME=pubsub-function" \
  --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

**Step 4: Deploy Cloud Storage triggered function (optional)**

```bash
gcloud functions deploy handleStorage \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=. \
  --entry-point=handleStorage \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=YOUR_BUCKET_NAME" \
  --memory=256Mi \
  --set-env-vars="OTEL_SERVICE_NAME=storage-function" \
  --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

## Configuration

| Variable | Description | Required |
|----------|-------------|----------|
| `OTEL_SERVICE_NAME` | Service name for telemetry | Yes |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint | Yes |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth header (from secret) | Yes |
| `SERVICE_VERSION` | Version tag for telemetry | No |
| `DEPLOYMENT_ENVIRONMENT` | Environment (prod/staging/dev) | No |

## Available Functions

| Function | Trigger | Description |
|----------|---------|-------------|
| `helloHttp` | HTTP | Simple greeting function |
| `processData` | HTTP POST | Data processing pipeline with nested spans |
| `handlePubSub` | Pub/Sub | Process messages from a topic |
| `handleStorage` | Cloud Storage | Process object create/delete events |

## Verification

Generate test traffic and verify in Last9:

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe helloHttp --gen2 --region=us-central1 --format='value(serviceConfig.uri)')

# Send requests
for i in {1..10}; do
  curl -s "$FUNCTION_URL?name=User$i"
  sleep 1
done

# Test Pub/Sub (if deployed)
gcloud pubsub topics publish my-topic --message='{"test": "message"}'
```

In Last9:
1. **Traces**: APM > Traces > Filter by service name
2. **Metrics**: View `function_invocations_total` and `function_duration_seconds`
3. **Logs**: Logs > Filter by function name

## Adding OpenTelemetry to Your Existing Function

1. **Add dependencies** to `package.json`:

```bash
npm install @google-cloud/functions-framework \
  @opentelemetry/api @opentelemetry/api-logs \
  @opentelemetry/sdk-node @opentelemetry/sdk-logs \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http \
  @opentelemetry/exporter-metrics-otlp-http \
  @opentelemetry/exporter-logs-otlp-http
```

2. **Copy `instrumentation.js`** to your project root

3. **Update your start script** in `package.json`:

```json
{
  "scripts": {
    "start": "node -r ./instrumentation.js node_modules/@google-cloud/functions-framework/build/src/main.js"
  }
}
```

4. **Add custom spans** to your function (optional):

```javascript
const { trace, SpanStatusCode } = require('@opentelemetry/api');
const tracer = trace.getTracer('my-function');

functions.http('myFunction', async (req, res) => {
  await tracer.startActiveSpan('businessLogic', async (span) => {
    span.setAttribute('custom.attribute', 'value');
    // Your code here
    span.end();
  });
  res.send('Done');
});
```

5. **Deploy with environment variables** for OTLP configuration
