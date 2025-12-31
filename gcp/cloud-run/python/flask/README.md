# Instrumenting Flask application on Cloud Run using OpenTelemetry

This example demonstrates how to integrate OpenTelemetry with a Flask application deployed to Google Cloud Run. The implementation provides automatic HTTP instrumentation, structured logging with trace correlation, and custom metrics exported to Last9 via OTLP.

## Prerequisites

- Python 3.9+
- Google Cloud SDK (`gcloud`)
- [Last9](https://app.last9.io) account with OTLP credentials

## Installation

1. Create a virtual environment and install dependencies:

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

2. Obtain the OTLP endpoint and Auth Header from the [Last9 dashboard](https://app.last9.io).

3. Set environment variables:

```bash
export OTEL_SERVICE_NAME=flask-cloud-run-demo
export OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"
```

## Running the Application

### Local Development

1. Run the application:

```bash
python app.py
```

2. Test the endpoints:

```bash
# Home
curl http://localhost:8080/

# Get all users
curl http://localhost:8080/users

# Get specific user
curl http://localhost:8080/users/1

# Test error handling
curl http://localhost:8080/error
```

Once the server is running, you can access the application at `http://localhost:8080` by default. The API endpoints are:

- GET `/` - Home page with service info
- GET `/users` - List all users
- GET `/users/<id>` - Get user by ID
- GET `/error` - Test error handling
- GET `/health` - Health check (no tracing)

### Deploy to Cloud Run

**Option 1: Using Cloud Build (Recommended)**

```bash
export PROJECT_ID=your-gcp-project
gcloud config set project $PROJECT_ID

# Create the Last9 auth secret (one-time setup)
# IMPORTANT: Include "Authorization=" prefix
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-

# Deploy using Cloud Build
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=flask-otel-demo,_REGION=us-central1,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
```

**Option 2: Direct Deploy**

```bash
gcloud run deploy flask-otel-demo \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 512Mi \
  --set-env-vars "OTEL_SERVICE_NAME=flask-cloud-run-demo" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

## Verify in Last9

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

### View Telemetry in Last9

1. Navigate to [Last9 APM Dashboard](https://app.last9.io/)
2. Select your service: `flask-cloud-run-demo`
3. View:
   - **Traces**: See distributed traces with spans
   - **Logs**: View structured logs with trace correlation
   - **Metrics**: Monitor request count and duration

## How to Add OpenTelemetry to an Existing Flask App on Cloud Run

To instrument your existing Flask application with OpenTelemetry for Cloud Run, follow these steps:

### 1. Install Required Packages

Add the following dependencies to your `requirements.txt`:

```txt
flask==3.0.0
opentelemetry-api==1.27.0
opentelemetry-sdk==1.27.0
opentelemetry-instrumentation-flask==0.48b0
opentelemetry-exporter-otlp-proto-http==1.27.0
```

Install the packages:

```bash
pip install -r requirements.txt
```

### 2. Create Telemetry Initialization Functions

Add these functions to your Flask app (or create a separate `telemetry.py` file):

```python
import os
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes

def get_cloud_run_resource():
    """Create resource with Cloud Run-specific attributes."""
    service_name = os.environ.get("OTEL_SERVICE_NAME") or os.environ.get("K_SERVICE") or "flask-cloud-run"

    return Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_VERSION: os.environ.get("SERVICE_VERSION", "1.0.0"),
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: os.environ.get("DEPLOYMENT_ENVIRONMENT", "production"),
        ResourceAttributes.CLOUD_PROVIDER: "gcp",
        ResourceAttributes.CLOUD_PLATFORM: "gcp_cloud_run_revision",
        ResourceAttributes.CLOUD_REGION: os.environ.get("CLOUD_RUN_REGION", os.environ.get("GOOGLE_CLOUD_REGION", "unknown")),
        ResourceAttributes.CLOUD_ACCOUNT_ID: os.environ.get("GOOGLE_CLOUD_PROJECT", "unknown"),
        ResourceAttributes.FAAS_NAME: os.environ.get("K_SERVICE", service_name),
        ResourceAttributes.FAAS_VERSION: os.environ.get("K_REVISION", "unknown"),
        ResourceAttributes.SERVICE_INSTANCE_ID: os.environ.get("K_REVISION", "local"),
    })

def parse_otlp_headers():
    """Parse OTLP headers from environment variable."""
    headers = {}
    headers_str = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")

    if headers_str:
        for pair in headers_str.split(","):
            if "=" in pair:
                key, value = pair.split("=", 1)
                headers[key.strip()] = value.strip()

    return headers

def initialize_telemetry():
    """Initialize OpenTelemetry tracing and metrics."""
    resource = get_cloud_run_resource()
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "https://your-otlp-endpoint")
    headers = parse_otlp_headers()

    # Initialize Tracing
    trace_exporter = OTLPSpanExporter(
        endpoint=f"{endpoint}/v1/traces",
        headers=headers,
    )
    trace_provider = TracerProvider(resource=resource)
    trace_provider.add_span_processor(
        BatchSpanProcessor(
            trace_exporter,
            max_export_batch_size=512,
            schedule_delay_millis=5000,  # 5 second delay for cold starts
        )
    )
    trace.set_tracer_provider(trace_provider)

    # Initialize Metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=f"{endpoint}/v1/metrics",
        headers=headers,
    )
    metric_reader = PeriodicExportingMetricReader(
        metric_exporter,
        export_interval_millis=60000,  # Export every 60 seconds
    )
    metric_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader],
    )
    metrics.set_meter_provider(metric_provider)

    return trace_provider, metric_provider
```

### 3. Initialize OpenTelemetry and Instrument Flask

In your `app.py`, initialize telemetry before creating the Flask app:

```python
from flask import Flask
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# Initialize telemetry FIRST
trace_provider, metric_provider = initialize_telemetry()

# Create Flask app
app = Flask(__name__)

# Instrument Flask
FlaskInstrumentor().instrument_app(app)

@app.route("/")
def home():
    return {"message": "Hello from Flask on Cloud Run!"}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
```

### 4. Add Custom Spans

To create custom spans in your routes:

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

@app.route("/users")
def get_users():
    # Create custom span
    with tracer.start_as_current_span("fetch_users_from_database") as span:
        span.set_attribute("db.system", "postgresql")
        span.set_attribute("db.operation", "SELECT")

        # Your database logic here
        users = fetch_users_from_db()

        return {"users": users}
```

### 5. Add Structured Logging

For trace-correlated logs:

```python
import json
import logging
from datetime import datetime
from opentelemetry import trace

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def structured_log(level, message, **kwargs):
    """Log with trace correlation for Cloud Logging."""
    span = trace.get_current_span()
    span_context = span.get_span_context()

    log_entry = {
        "severity": level,
        "message": message,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        **kwargs
    }

    # Add trace correlation
    if span_context.is_valid:
        project_id = os.environ.get("GOOGLE_CLOUD_PROJECT")
        if project_id:
            trace_id = format(span_context.trace_id, "032x")
            span_id = format(span_context.span_id, "016x")
            log_entry["logging.googleapis.com/trace"] = f"projects/{project_id}/traces/{trace_id}"
            log_entry["logging.googleapis.com/spanId"] = span_id

    print(json.dumps(log_entry))

# Use in routes
@app.route("/users")
def get_users():
    structured_log("INFO", "Fetching all users")
    # ... your code
```

### 6. Add Graceful Shutdown

Ensure telemetry is flushed before shutdown:

```python
import atexit
import signal

def shutdown_telemetry():
    """Flush telemetry on shutdown."""
    trace_provider.force_flush()
    metric_provider.force_flush()
    trace_provider.shutdown()
    metric_provider.shutdown()

# Register shutdown handlers
atexit.register(shutdown_telemetry)
signal.signal(signal.SIGTERM, lambda *args: shutdown_telemetry())
```

### 7. Set Environment Variables

Configure your Cloud Run service:

```bash
gcloud run services update YOUR_SERVICE_NAME \
  --set-env-vars "OTEL_SERVICE_NAME=your-service-name" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 8. Deploy and Verify

Deploy your instrumented application:

```bash
gcloud run deploy YOUR_SERVICE_NAME \
  --source . \
  --region us-central1
```

Generate traffic and verify traces, logs, and metrics appear in Last9.

---

**Tip:** For a complete working example, see the files in this repository:
- `app.py` - Flask app with full OpenTelemetry instrumentation
- `requirements.txt` - Python dependencies
- `Dockerfile` - Container build configuration

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
