# Node.js Express on Cloud Run with OpenTelemetry

Deploy an Express application to Google Cloud Run with complete OpenTelemetry instrumentation, sending **traces, logs, and metrics** to Last9 via OTLP.

## Features

### Traces
- ✓ Automatic HTTP/Express request instrumentation
- ✓ Custom spans for business logic (database queries, etc.)
- ✓ Error tracking and exception recording
- ✓ Distributed tracing context propagation

### Logs
- ✓ OTLP logs export to Last9 with automatic trace correlation
- ✓ Structured JSON logging to Cloud Logging
- ✓ Severity levels (INFO, WARNING, ERROR)
- ✓ Custom attributes per log message

### Metrics
- ✓ HTTP request count and duration histograms
- ✓ Custom application metrics
- ✓ Runtime metrics (available via instrumentation)

### Infrastructure
- ✓ Cloud Run resource detection (service, revision, region)
- ✓ Graceful shutdown for reliable telemetry export
- ✓ Batch processing for optimal performance

## Prerequisites

- Node.js 18+
- Google Cloud SDK (`gcloud`)
- Docker (for local testing)
- Last9 account with OTLP credentials

## Local Development

### 1. Install dependencies

```bash
npm install
```

### 2. Configure environment variables

```bash
cp .env.example .env
# Edit .env with your Last9 credentials
```

```bash
export OTEL_SERVICE_NAME=express-cloud-run-demo

# Set your OTLP endpoint
export OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT

export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_BASE64_CREDENTIALS"
```

**Finding your Last9 credentials:**
1. Log in to Last9 console
2. Navigate to Settings → Integrations → OTLP
3. Copy the base64-encoded credentials

### 3. Run locally

```bash
npm start
```

### 4. Test endpoints

```bash
# Health check
curl http://localhost:8080/health

# Home
curl http://localhost:8080/

# Get users
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

## Deploy to Cloud Run

### Option 1: Using Cloud Build (Recommended)

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
  --substitutions=_SERVICE_NAME=cloud-run-nodejs-express,_REGION=$REGION
```

**Note:** The `cloudbuild.yaml` will automatically:
- Build the Docker image
- Push to Google Container Registry
- Deploy to Cloud Run with proper environment variables
- Configure secrets from Secret Manager

### Option 2: Direct Deploy

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

## Verify Telemetry

### Generate Traffic

**Option 1: Using the traffic generator script**

```bash
# Generate 2 minutes of realistic traffic (5 requests/second)
./generate-traffic.sh 120 5
```

The script generates a realistic traffic mix:
- 40% home endpoint (`/`)
- 30% list users (`/users`)
- 15% get user by ID (`/users/:id`)
- 10% create user (POST `/users`)
- 5% error endpoint (`/error`)

**Option 2: Manual testing**

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

### View in Last9

1. Navigate to Last9 console
2. **Traces**: APM → Traces → Filter by service name `cloud-run-nodejs-express`
3. **Logs**: Logs → Filter by `service.name="cloud-run-nodejs-express"`
4. **Metrics**: Dashboards → Create dashboard with:
   - `http_requests_total` (request count)
   - `http_request_duration_seconds` (latency)
   - Infrastructure metrics from Grafana Alloy (CPU, memory, etc.)

**What to look for:**
- Traces showing HTTP request spans with duration
- Logs correlated with traces (same traceId)
- Custom spans for database queries
- Error traces from `/error` endpoint

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Home page with service info |
| `/users` | GET | List all users |
| `/users/:id` | GET | Get user by ID |
| `/users` | POST | Create new user |
| `/error` | GET | Test error handling |
| `/health` | GET | Health check (no tracing) |
| `/ready` | GET | Readiness check |

## How Instrumentation Works

The `instrumentation.js` file must be loaded **before** any other modules. This is done via the `-r` flag:

```bash
node -r ./instrumentation.js app.js
```

### Instrumentation Flow

1. **Resource Detection**: Automatically detects Cloud Run environment variables:
   - `K_SERVICE` → Service name
   - `K_REVISION` → Revision name
   - `GOOGLE_CLOUD_PROJECT` → Project ID
   - Creates semantic resource attributes following OpenTelemetry conventions

2. **OTLP Exporters Setup**:
   - **Traces**: `OTLPTraceExporter` → `${endpoint}/v1/traces`
   - **Metrics**: `OTLPMetricExporter` → `${endpoint}/v1/metrics`
   - **Logs**: `OTLPLogExporter` → `${endpoint}/v1/logs`

3. **Auto-Instrumentation**:
   - HTTP/HTTPS requests (client & server)
   - Express framework
   - Automatically disabled: fs, dns (too noisy)
   - Ignores: `/health`, `/ready`, `/_ah/health`

4. **Batch Processing**:
   - Traces: 512 spans per batch, 5s delay
   - Metrics: Export every 60s
   - Logs: 512 logs per batch, 5s delay

5. **Graceful Shutdown**:
   - Listens for `SIGTERM`/`SIGINT`
   - Flushes all pending telemetry before exit
   - Critical for Cloud Run (request-based scaling)

### Logging Implementation

The `structuredLog()` function in `app.js`:
- Emits logs via OpenTelemetry Logs API
- Automatically includes trace context (traceId, spanId)
- Dual output: OTLP (to Last9) + console.log (to Cloud Logging)
- Supports severity levels: INFO, WARNING, ERROR, DEBUG

## Files

| File | Description |
|------|-------------|
| `instrumentation.js` | OpenTelemetry SDK setup (must load first) |
| `app.js` | Express application with structured logging |
| `package.json` | Dependencies including OTLP exporters |
| `Dockerfile` | Multi-stage container build |
| `cloudbuild.yaml` | Cloud Build configuration for GCP |
| `generate-traffic.sh` | Traffic generator for testing |

## Dependencies

Key OpenTelemetry packages:

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
