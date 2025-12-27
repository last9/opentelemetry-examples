# Python Flask on Cloud Run with OpenTelemetry

Deploy a Flask application to Google Cloud Run with full OpenTelemetry instrumentation, sending traces, logs, and metrics to Last9.

## Features

- Automatic Flask request instrumentation
- Custom spans for business logic
- Structured JSON logging with trace correlation
- HTTP request metrics (count, duration)
- Cloud Run resource detection
- Graceful shutdown for reliable telemetry export

## Prerequisites

- Python 3.9+
- Google Cloud SDK (`gcloud`)
- Docker (for local testing)
- Last9 account with OTLP credentials

## Local Development

### 1. Set up environment

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure environment variables

```bash
cp .env.example .env
# Edit .env with your Last9 credentials
```

```bash
export OTEL_SERVICE_NAME=flask-cloud-run-demo
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"
```

### 3. Run locally

```bash
python app.py
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

# Test error handling
curl http://localhost:8080/error
```

## Deploy to Cloud Run

### Option 1: Using Cloud Build (Recommended)

```bash
# Set your project
export PROJECT_ID=your-gcp-project
gcloud config set project $PROJECT_ID

# Create the Last9 auth secret (one-time setup)
echo -n "Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Deploy using Cloud Build
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=flask-otel-demo,_REGION=us-central1
```

### Option 2: Direct Deploy

```bash
# Build and deploy in one command
gcloud run deploy flask-otel-demo \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 512Mi \
  --set-env-vars "OTEL_SERVICE_NAME=flask-cloud-run-demo" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### Option 3: Using service.yaml

```bash
# Update PROJECT_ID in service.yaml
sed -i "s/PROJECT_ID/$PROJECT_ID/g" service.yaml

# Build the image
gcloud builds submit --tag gcr.io/$PROJECT_ID/flask-otel-demo

# Deploy the service
gcloud run services replace service.yaml --region us-central1
```

## Verify Telemetry

### Generate Traffic

```bash
# Get the service URL
SERVICE_URL=$(gcloud run services describe flask-otel-demo --region us-central1 --format 'value(status.url)')

# Make some requests
for i in {1..10}; do
  curl -s "$SERVICE_URL/users" > /dev/null
  curl -s "$SERVICE_URL/users/$i" > /dev/null
  sleep 1
done
```

### View in Last9

1. Navigate to [Last9 APM Dashboard](https://app.last9.io/)
2. Select your service: `flask-cloud-run-demo`
3. View:
   - **Traces**: See distributed traces with spans
   - **Logs**: View structured logs with trace correlation
   - **Metrics**: Monitor request count and duration

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Home page with service info |
| `/users` | GET | List all users |
| `/users/<id>` | GET | Get user by ID |
| `/error` | GET | Test error handling |
| `/health` | GET | Health check (no tracing) |
| `/ready` | GET | Readiness check |

## Telemetry Details

### Traces

The application creates the following spans:

- `GET /users` - Automatic Flask instrumentation
- `fetch_users_from_database` - Custom span for simulated DB query
- `fetch_user_by_id` - Custom span with user ID attribute

### Metrics

Custom metrics exported:

| Metric | Type | Description |
|--------|------|-------------|
| `http_requests_total` | Counter | Total HTTP requests by method, route, status |
| `http_request_duration_seconds` | Histogram | Request duration distribution |

### Logs

Structured JSON logs with trace correlation:

```json
{
  "severity": "INFO",
  "message": "Returning 3 users",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "logging.googleapis.com/trace": "projects/my-project/traces/abc123",
  "logging.googleapis.com/spanId": "def456"
}
```

## Resource Attributes

The following resource attributes are automatically set:

| Attribute | Value |
|-----------|-------|
| `service.name` | `OTEL_SERVICE_NAME` env var |
| `service.version` | `SERVICE_VERSION` env var |
| `cloud.provider` | `gcp` |
| `cloud.platform` | `gcp_cloud_run_revision` |
| `cloud.region` | `CLOUD_RUN_REGION` env var |
| `cloud.account.id` | `GOOGLE_CLOUD_PROJECT` env var |
| `faas.name` | `K_SERVICE` env var |
| `faas.version` | `K_REVISION` env var |

## Troubleshooting

### Traces not appearing

1. Check environment variables:
   ```bash
   gcloud run services describe flask-otel-demo --region us-central1 \
     --format 'yaml(spec.template.spec.containers[0].env)'
   ```

2. Verify secret access:
   ```bash
   gcloud secrets versions access latest --secret=last9-auth-header
   ```

3. Check Cloud Run logs:
   ```bash
   gcloud run services logs read flask-otel-demo --region us-central1 --limit 50
   ```

### Cold start latency

The application uses `BatchSpanProcessor` with a 5-second delay. For immediate export on cold starts, consider:

1. Increasing min instances to 1
2. Using `SimpleSpanProcessor` (higher overhead, guaranteed delivery)

### Memory issues

If experiencing OOM:
- Increase memory to 1Gi
- Reduce batch size in `BatchSpanProcessor`
- Decrease metric export interval

## Files

| File | Description |
|------|-------------|
| `app.py` | Flask application with OTEL instrumentation |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build configuration |
| `service.yaml` | Cloud Run service definition |
| `cloudbuild.yaml` | Cloud Build configuration |
| `.env.example` | Environment variables template |
