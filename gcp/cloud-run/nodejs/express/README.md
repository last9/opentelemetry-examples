# Node.js Express on Cloud Run with OpenTelemetry

Deploy an Express application to Google Cloud Run with full OpenTelemetry instrumentation, sending traces, logs, and metrics to Last9.

## Features

- Automatic HTTP/Express request instrumentation
- Custom spans for business logic
- Structured JSON logging with trace correlation
- HTTP request metrics (count, duration)
- Cloud Run resource detection
- Graceful shutdown for reliable telemetry export

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
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"
```

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
gcloud config set project $PROJECT_ID

# Create the Last9 auth secret (one-time setup)
echo -n "Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Deploy using Cloud Build
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=express-otel-demo,_REGION=us-central1
```

### Option 2: Direct Deploy

```bash
gcloud run deploy express-otel-demo \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 512Mi \
  --set-env-vars "OTEL_SERVICE_NAME=express-cloud-run-demo" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io" \
  --set-env-vars "NODE_ENV=production" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

## Verify Telemetry

### Generate Traffic

```bash
SERVICE_URL=$(gcloud run services describe express-otel-demo --region us-central1 --format 'value(status.url)')

for i in {1..10}; do
  curl -s "$SERVICE_URL/users" > /dev/null
  curl -s "$SERVICE_URL/users/$i" > /dev/null
  sleep 1
done
```

### View in Last9

1. Navigate to [Last9 APM Dashboard](https://app.last9.io/)
2. Select your service: `express-cloud-run-demo`
3. View traces, logs, and metrics

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

The instrumentation file:
1. Creates Cloud Run-specific resource attributes
2. Configures OTLP exporters for traces and metrics
3. Sets up auto-instrumentation for Express, HTTP, and more
4. Registers graceful shutdown handlers

## Files

| File | Description |
|------|-------------|
| `instrumentation.js` | OpenTelemetry SDK setup (loaded first) |
| `app.js` | Express application |
| `package.json` | Dependencies and scripts |
| `Dockerfile` | Container build configuration |
| `service.yaml` | Cloud Run service definition |
| `cloudbuild.yaml` | Cloud Build configuration |
| `.env.example` | Environment variables template |
