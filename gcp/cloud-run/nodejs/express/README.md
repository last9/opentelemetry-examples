# Instrumenting Express application on Cloud Run using OpenTelemetry

This example demonstrates how to integrate OpenTelemetry with an Express application deployed to Google Cloud Run. The implementation provides automatic HTTP instrumentation, structured logging with trace correlation, and custom metrics exported to Last9 via OTLP.

## Prerequisites

- Node.js 18+
- Google Cloud SDK (`gcloud`)
- [Last9](https://app.last9.io) account with OTLP credentials

## Installation

1. Install dependencies:

```bash
npm install
```

2. Obtain the OTLP endpoint and Auth Header from the [Last9 dashboard](https://app.last9.io).

3. Set environment variables:

```bash
export OTEL_SERVICE_NAME=express-cloud-run-demo
export OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_BASE64_CREDENTIALS"
```

**Finding your Last9 credentials:**
1. Log in to Last9 console
2. Navigate to Settings → Integrations → OTLP
3. Copy the OTLP endpoint and base64-encoded credentials

## Running the Application

### Local Development

1. Run the application:

```bash
npm start
```

2. Test the endpoints:

```bash
# Home
curl http://localhost:8080/

# Get all users
curl http://localhost:8080/users

# Get specific user
curl http://localhost:8080/users/1

# Create user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Dave", "email": "dave@example.com"}'

# Test error handling
curl http://localhost:8080/error
```

Once the server is running, you can access the application at `http://localhost:8080` by default. The API endpoints are:

- GET `/` - Home page with service info
- GET `/users` - List all users
- GET `/users/:id` - Get user by ID
- POST `/users` - Create new user
- GET `/error` - Test error handling
- GET `/health` - Health check (no tracing)

### Deploy to Cloud Run

**Option 1: Using Cloud Build (Recommended)**

```bash
export PROJECT_ID=your-gcp-project
export REGION=us-central1
gcloud config set project $PROJECT_ID

# Create the Last9 auth secret (one-time setup)
# IMPORTANT: Include "Authorization=" prefix
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Verify secret was created correctly
gcloud secrets versions access latest --secret=last9-auth-header

# Deploy using Cloud Build
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=cloud-run-nodejs-express,_REGION=$REGION,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
```

**Option 2: Direct Deploy**

```bash
gcloud run deploy cloud-run-nodejs-express \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 512Mi \
  --set-env-vars "OTEL_SERVICE_NAME=cloud-run-nodejs-express" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-env-vars "NODE_ENV=production" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

## Verify in Last9

### Generate Traffic

**Using the traffic generator script:**

```bash
# Generate 2 minutes of realistic traffic (5 requests/second)
./generate-traffic.sh 120 5
```

**Manual testing:**

```bash
SERVICE_URL=$(gcloud run services describe cloud-run-nodejs-express \
  --region us-central1 --format 'value(status.url)')

# Send test requests
for i in {1..10}; do
  curl -s "$SERVICE_URL/users" > /dev/null
  curl -s "$SERVICE_URL/users/$i" > /dev/null
  sleep 1
done
```

### View Telemetry in Last9

1. Navigate to [Last9 APM Dashboard](https://app.last9.io/)
2. **Traces**: APM → Traces → Filter by service name `cloud-run-nodejs-express`
3. **Logs**: Logs → Filter by `service.name="cloud-run-nodejs-express"`
4. **Metrics**: Dashboards → Create dashboard with `http_requests_total` and `http_request_duration_seconds`

You should see:
- Traces showing HTTP request spans with duration
- Logs correlated with traces (same traceId)
- Custom spans for database queries
- Error traces from `/error` endpoint

## How to Add OpenTelemetry to an Existing Express App on Cloud Run

To instrument your existing Express application with OpenTelemetry for Cloud Run, follow these steps:

### 1. Install Required Packages

Add the following dependencies to your project:

```bash
npm install \
  @opentelemetry/api@^1.9.0 \
  @opentelemetry/api-logs@^0.53.0 \
  @opentelemetry/sdk-node@^0.53.0 \
  @opentelemetry/sdk-logs@^0.53.0 \
  @opentelemetry/auto-instrumentations-node@^0.50.0 \
  @opentelemetry/exporter-trace-otlp-http@^0.53.0 \
  @opentelemetry/exporter-metrics-otlp-http@^0.53.0 \
  @opentelemetry/exporter-logs-otlp-http@^0.53.0
```

### 2. Create Instrumentation File

**Copy the `instrumentation.js` file from this repository into your project root.** This file sets up the OpenTelemetry SDK with:

- OTLP HTTP exporters for traces, metrics, and logs
- Cloud Run resource detection (service name, revision, region)
- Auto-instrumentation for Express and HTTP
- Batch processing with appropriate delays for cold starts
- Graceful shutdown handlers

The instrumentation file includes:

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
// ... other imports

// Create Cloud Run resource with semantic attributes
function createCloudRunResource() {
  const serviceName = process.env.OTEL_SERVICE_NAME || process.env.K_SERVICE || 'nodejs-cloud-run';

  return Resource.default().merge(
    new Resource({
      [SEMRESATTRS_SERVICE_NAME]: serviceName,
      'cloud.provider': 'gcp',
      'cloud.platform': 'gcp_cloud_run_revision',
      'cloud.region': process.env.CLOUD_RUN_REGION || process.env.GOOGLE_CLOUD_REGION,
      'faas.name': process.env.K_SERVICE,
      'faas.version': process.env.K_REVISION,
      // ... other attributes
    })
  );
}

// Initialize and start SDK
const sdk = new NodeSDK({
  resource: createCloudRunResource(),
  spanProcessor: new BatchSpanProcessor(traceExporter, {
    maxExportBatchSize: 512,
    scheduledDelayMillis: 5000,
  }),
  // ... other configuration
});

sdk.start();
```

### 3. Update package.json Start Command

Modify your `package.json` to load instrumentation before your app:

```json
{
  "scripts": {
    "start": "node -r ./instrumentation.js app.js"
  }
}
```

The `-r` flag loads `instrumentation.js` before any other modules, ensuring all HTTP requests are automatically instrumented.

### 4. Add Structured Logging (Optional)

For trace-correlated logs, add this function to your Express app:

```javascript
const { trace } = require('@opentelemetry/api');
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');

const logger = logs.getLogger('my-express-app', '1.0.0');

function structuredLog(level, message, extra = {}) {
  const span = trace.getActiveSpan();
  const spanContext = span ? span.spanContext() : null;

  // Emit log via OpenTelemetry
  const logRecord = {
    severityNumber: SeverityNumber[level] || SeverityNumber.INFO,
    severityText: level,
    body: message,
    attributes: extra,
  };

  if (spanContext) {
    logRecord.spanId = spanContext.spanId;
    logRecord.traceId = spanContext.traceId;
    logRecord.traceFlags = spanContext.traceFlags;
  }

  logger.emit(logRecord);

  // Also log to console for Cloud Logging
  const logEntry = {
    severity: level,
    message,
    timestamp: new Date().toISOString(),
    ...extra,
  };

  if (spanContext && spanContext.traceId) {
    const projectId = process.env.GOOGLE_CLOUD_PROJECT;
    if (projectId) {
      logEntry['logging.googleapis.com/trace'] = `projects/${projectId}/traces/${spanContext.traceId}`;
      logEntry['logging.googleapis.com/spanId'] = spanContext.spanId;
    }
  }

  console.log(JSON.stringify(logEntry));
}

// Use in your routes
app.get('/users', (req, res) => {
  structuredLog('INFO', 'Fetching all users');
  // ... your code
});
```

### 5. Set Environment Variables

Configure your Cloud Run service with the required environment variables:

```bash
gcloud run services update YOUR_SERVICE_NAME \
  --set-env-vars "OTEL_SERVICE_NAME=your-service-name" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 6. Deploy and Verify

Deploy your instrumented application:

```bash
gcloud run deploy YOUR_SERVICE_NAME \
  --source . \
  --region us-central1
```

Generate traffic and verify traces, logs, and metrics appear in Last9.

---

**Tip:** For a complete working example, see the files in this repository:
- `instrumentation.js` - Full OpenTelemetry SDK setup
- `app.js` - Express app with structured logging
- `package.json` - Dependencies and scripts

## Instrumentation Details

### How It Works

The `instrumentation.js` file handles:

1. **Resource Detection**: Automatically detects Cloud Run environment variables (`K_SERVICE`, `K_REVISION`, `GOOGLE_CLOUD_PROJECT`) and creates semantic resource attributes

2. **OTLP Exporters**: Configures HTTP exporters for traces, metrics, and logs pointing to `${endpoint}/v1/traces`, `${endpoint}/v1/metrics`, and `${endpoint}/v1/logs`

3. **Auto-Instrumentation**: Automatically instruments HTTP/HTTPS requests and Express framework. Disables noisy instrumentations (fs, dns) and ignores health check endpoints

4. **Batch Processing**: Uses batch processors with 5-second delays to handle cold starts gracefully

5. **Graceful Shutdown**: Listens for `SIGTERM`/`SIGINT` and flushes all pending telemetry before exit

### Dependencies

Key OpenTelemetry packages used:

```json
{
  "@opentelemetry/api": "^1.9.0",
  "@opentelemetry/api-logs": "^0.53.0",
  "@opentelemetry/sdk-node": "^0.53.0",
  "@opentelemetry/sdk-logs": "^0.53.0",
  "@opentelemetry/auto-instrumentations-node": "^0.50.0",
  "@opentelemetry/exporter-trace-otlp-http": "^0.53.0",
  "@opentelemetry/exporter-metrics-otlp-http": "^0.53.0",
  "@opentelemetry/exporter-logs-otlp-http": "^0.53.0"
}
```
