# GCP Pub/Sub, Storage & Content API with OpenTelemetry Demo

This example demonstrates OpenTelemetry instrumentation for Google Cloud Platform services including:
- Cloud Pub/Sub (Publisher & Subscriber)
- Cloud Storage (Object upload)
- **Google Content API for Shopping (Promotions)** - *NEW*

All telemetry data is sent to Last9 via OTLP, with support for LocalStack-style local development.

## ✨ New Features

### Google Content API Integration
- **Custom instrumentation** for `content.promotions.create` API calls
- **Proper span attributes** with service name, version, merchant ID
- **Error handling and recording** in OpenTelemetry spans
- **Mock support** for local development without GCP credentials

### Enhanced Configuration & Error Handling
- **Configurable service name** via `OTEL_SERVICE_NAME` environment variable
- **Improved bucket creation** with graceful handling of existing buckets
- **Better error messages** for resource creation and conflicts
- **Unique bucket name support** for avoiding global naming conflicts

The application now performs: Cloud Storage upload → Pub/Sub publish → Pub/Sub subscribe → **Content API promotion creation**. You can run it in two modes:

- **CLI mode (default)**: one-shot Storage Upload -> Pub/Sub Publish -> Pub/Sub Subscribe -> process
- **Server mode**: a Gin HTTP server with `/demo` and `/health` endpoints. `/demo` triggers the same workflow and returns JSON.

## Prerequisites
- Recent version of Go
- Docker and Docker Compose for local testing
- Google Cloud credentials for real GCP testing (optional)
- An OTLP endpoint (e.g., Last9) if you want to view traces

## Libraries
- Google Cloud Go SDK
- OpenTelemetry Go SDK  
- `go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc`
- `go.opentelemetry.io/contrib/detectors/gcp`

## API Endpoints

### Health Check
```bash
curl http://localhost:8080/health
```

### GCP Services Demo (Pub/Sub + Storage)
```bash
curl -X POST http://localhost:8080/demo \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "demo-bucket",
    "object_name": "test.txt",
    "topic_name": "demo-topic",
    "subscription_name": "demo-subscription"
  }'
```

### Content API Promotions (NEW)
```bash
curl -X POST http://localhost:8080/promotion \
  -H "Content-Type: application/json" \
  -d '{
    "merchant_id": 123456789
  }'
```

## Traces
The app creates a **hierarchical trace structure** with these spans:
- **Root span**: `gcp cloud client demo` (parent for all operations)
- **Storage span**: `upload object to GCS` (with semantic attributes)
- **Publisher span**: `publish message to Pub/Sub` (with messaging attributes)
- **Subscriber span**: `receive message from Pub/Sub` (with messaging attributes)
- **Consumer span**: `process Pub/Sub message` (linked via W3C context propagation)
- **Content API span**: `content.promotions.create` (with Content API attributes) ⭐ **NEW**

All spans are properly nested under the root span, creating a single cohesive trace in Last9.

## Install dependencies
```bash
cd go/gcp-pubsub-storage-content
go mod tidy
```

## 🚀 Viewing Traces in Last9 

Last9 provides a comprehensive observability platform for viewing and analyzing your traces. Follow these steps:

### Step 1: Configure Last9 OTLP Endpoint
Set these environment variables before running the application:
```bash
# Service name (customize as needed)
export OTEL_SERVICE_NAME="gcp-content-promotions-demo"

# Last9 OTLP configuration
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_LAST9_BASIC_AUTH_TOKEN>"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=demo,service.version=1.0.0"
```

**Note**: The service name is now configurable via `OTEL_SERVICE_NAME`. If not set, defaults to `gcp-pubsub-storage-demo`.

### Step 1b: Configure Google Cloud (Optional for Production)
For real Content API calls (not mocked):
```bash
export GOOGLE_CLOUD_PROJECT="your-project-id"
export GOOGLE_MERCHANT_ID="your-merchant-center-id"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

### Step 2: View Traces
After running your application:
1. Open [Last9 Dashboard](https://app.last9.io)
2. Navigate to **APM** → **Traces**
3. Filter by service name: Use your configured `OTEL_SERVICE_NAME` value
4. Look for these operation names:
   - `GET /health` - Health check requests
   - `POST /demo` - GCP services workflow
   - `POST /promotion` - Content API promotion creation ⭐
   - `content.promotions.create` - Individual Content API calls ⭐
   - `upload object to GCS` - Storage operations
   - `publish message to Pub/Sub` - Pub/Sub publishing

## Running against Google Cloud (CLI mode)
Set your project and resource names:
```bash
export GOOGLE_CLOUD_PROJECT=<your-project-id>
export GCS_BUCKET=<your-bucket>
export PUBSUB_TOPIC=<your-topic>
export PUBSUB_SUBSCRIPTION=<your-subscription>

go run .
```

## 🏠 Local Development with Emulators (LocalStack Equivalent)

This setup provides a complete local development environment similar to LocalStack but for Google Cloud services.

### Step 1: Start the Local Environment
```bash
# Start all emulators and trace collection
docker-compose up -d

# Verify all services are running
docker-compose ps
```

This starts:
- **fake-gcs-server** on port 4443 (Cloud Storage emulator - LocalStack equivalent)
- **Pub/Sub emulator** on port 8085 (official Google Cloud emulator) 
- **Jaeger UI** on port 16686 (optional local trace viewing)

### Step 2: Configure Environment for Local Development
```bash
# Local emulator endpoints
export STORAGE_EMULATOR_HOST=localhost:4443
export PUBSUB_EMULATOR_HOST=localhost:8085

# Demo project configuration
export GOOGLE_CLOUD_PROJECT=demo-project
export GCS_BUCKET=demo-bucket
export PUBSUB_TOPIC=demo-topic
export PUBSUB_SUBSCRIPTION=demo-subscription

# Configure trace destination:
export OTEL_EXPORTER_OTLP_ENDPOINT="Last9 OTLP Endpoint"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
```

### Step 3: Run the Application (CLI Mode)
```bash
go run .
```

The application will automatically:
- Create the GCS bucket if it doesn't exist
- Create the Pub/Sub topic and subscription
- Perform the complete workflow: Storage upload → Pub/Sub publish → consume → process

### Step 4: Check Local Emulator Status
```bash
# Verify GCS emulator
curl http://localhost:4443/storage/v1/

# Verify Pub/Sub emulator
curl http://localhost:8085
```

## 🌐 Server Mode (HTTP API) with Emulators

### Step 1: Start Local Environment
```bash
docker-compose up -d
```

### Step 2: Start the HTTP Server
```bash
# Set emulator endpoints  
export STORAGE_EMULATOR_HOST=localhost:4443
export PUBSUB_EMULATOR_HOST=localhost:8085
export GOOGLE_CLOUD_PROJECT=demo-project
export GCS_BUCKET=demo-bucket
export PUBSUB_TOPIC=demo-topic
export PUBSUB_SUBSCRIPTION=demo-subscription

# Configure tracing
export OTEL_EXPORTER_OTLP_ENDPOINT="Last9 OTLP Endpoint"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"

# Server configuration
export RUN_SERVER=true
export PORT=8080

# Start the server
go run .
```

### Step 3: Test the API Endpoints
```bash
# Health check
curl http://localhost:8080/health

# Test Content API promotion creation (NEW)
curl -X POST http://localhost:8080/promotion \
  -H 'Content-Type: application/json' \
  -d '{"merchant_id": 123456789}'

# Run GCP workflow with custom resource names
curl -X POST http://localhost:8080/demo \
  -H 'Content-Type: application/json' \
  -d '{
    "bucket": "my-analytics-bucket",
    "object_name": "user-events.json",
    "topic_name": "user-events-topic", 
    "subscription_name": "events-processor"
  }'

# Use default demo names
curl -X POST http://localhost:8080/demo \
  -H 'Content-Type: application/json' \
  -d '{
    "bucket": "demo-bucket",
    "object_name": "test.txt",
    "topic_name": "demo-topic", 
    "subscription_name": "demo-subscription"
  }'

# Or use environment variables (empty JSON body)
curl -X POST http://localhost:8080/demo \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**✨ Dynamic Resource Creation**: The API automatically creates buckets, topics, and subscriptions in the emulators using the names you provide - no need to pre-create them!

The API returns a JSON response with the workflow status and resource names used.


## 🚀 Complete LocalStack + Last9 Testing Guide

### Quick Start: Content API with LocalStack + Last9

```bash
# 1. Start local emulator environment
docker-compose up -d

# 2. Configure LocalStack emulators
export STORAGE_EMULATOR_HOST=localhost:4443
export PUBSUB_EMULATOR_HOST=localhost:8085
export GOOGLE_CLOUD_PROJECT=demo-project

# 3. Configure Last9 tracing (REPLACE WITH YOUR CREDENTIALS)
export OTEL_SERVICE_NAME="my-custom-service-name"  # Customize as needed
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_LAST9_BASIC_AUTH_TOKEN>"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=localstack,service.version=1.0.0"

# 4. Start the HTTP server
export RUN_SERVER=true
export PORT=8080
go run . &

# 5. Test Content API (will use mock data since no GCP credentials)
curl -X POST http://localhost:8080/promotion \
  -H 'Content-Type: application/json' \
  -d '{"merchant_id": 123456789}'

# 6. Test GCP services workflow
curl -X POST http://localhost:8080/demo \
  -H 'Content-Type: application/json' \
  -d '{
    "bucket": "test-bucket",
    "object_name": "localstack-test.txt",
    "topic_name": "test-topic",
    "subscription_name": "test-subscription"
  }'

# 7. View traces in Last9
# Visit https://app.last9.io > APM > Traces  
# Filter by service: my-custom-service-name (or whatever you set OTEL_SERVICE_NAME to)
```

### Production Testing with Real GCP + Last9

```bash
# 1. Configure Google Cloud credentials
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
export GOOGLE_CLOUD_PROJECT="your-actual-project-id"
export GOOGLE_MERCHANT_ID="your-merchant-center-id"

# 2. Configure real GCP resources
export GCS_BUCKET="your-production-bucket"
export PUBSUB_TOPIC="your-production-topic"
export PUBSUB_SUBSCRIPTION="your-production-subscription"

# 3. Configure Last9 (same as above)
export OTEL_SERVICE_NAME="my-production-service"  # Customize as needed
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_LAST9_BASIC_AUTH_TOKEN>"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=production,service.version=1.0.0"

# 4. Start server and test
export RUN_SERVER=true
go run . &

# 5. Test with real Content API calls
curl -X POST http://localhost:8080/promotion \
  -H 'Content-Type: application/json' \
  -d '{"merchant_id": YOUR_ACTUAL_MERCHANT_ID}'
```

### Server Mode Testing  
```bash
# Same environment setup as above, then:
export RUN_SERVER=true
export PORT=8080
go run . &

# Test the API
curl -X POST http://localhost:8080/demo -H 'Content-Type: application/json' -d '{}'

# Check traces in Last9 dashboard
```

### Trace Verification Checklist
After running the workflow, verify these spans appear in Last9 **under a single trace**:

#### For `/promotion` endpoint:
✅ **HTTP Span**: `POST /promotion` (HTTP request span)  
└── ✅ **Content API Span**: `content.promotions.create` (with Content API attributes) ⭐

#### For `/demo` endpoint:
✅ **HTTP Span**: `POST /demo` (HTTP request span)  
├── ✅ **Storage Span**: `upload object to GCS` (with cloud resource attributes)  
├── ✅ **Publish Span**: `publish message to Pub/Sub` (with messaging attributes)  
├── ✅ **Subscribe Span**: `receive message from Pub/Sub` (with messaging attributes)  
└── ✅ **Consumer Span**: `process Pub/Sub message` (linked via W3C context)

**Key Success Indicators:**
- All spans share the **same trace ID** 
- Spans are properly **nested/hierarchical** (not separate traces)
- **Semantic attributes** are populated:
  - Content API: `service.name=content-api`, `service.version=v2.1`, merchant ID
  - Storage: cloud resource IDs, bucket names
  - Pub/Sub: messaging destinations, topic/subscription names
- **Mock vs Real**: Look for "mock-promotion-123" vs real promotion IDs
- **Error handling**: Failed requests show proper error attributes and status codes

### Cleanup
```bash
docker-compose down
```

## 🔧 Troubleshooting

### Common Issues

**Traces not appearing in Last9:**
- Verify `OTEL_EXPORTER_OTLP_HEADERS` is correctly Base64 encoded
- Check Last9 token has proper permissions  
- Ensure service name matches your `OTEL_SERVICE_NAME` environment variable

**Service name not appearing correctly:**
- Check that `OTEL_SERVICE_NAME` is set before starting the application
- If not set, the application defaults to `gcp-pubsub-storage-demo`
- Restart the application after changing the environment variable

**Emulator connection errors:**
```bash
# Verify emulators are running
docker-compose ps

# Check emulator endpoints
curl http://localhost:4443/storage/v1/  # GCS emulator
curl http://localhost:8085              # Pub/Sub emulator
```

**Bucket creation errors:**
```bash
# Error: "A Cloud Storage bucket named 'demo-bucket' already exists"
# Solution: Use a unique bucket name
export GCS_BUCKET="my-unique-bucket-name-$(date +%s)"

# Or via API request:
curl -X POST http://localhost:8080/demo -H 'Content-Type: application/json' \
  -d '{"bucket": "my-unique-bucket-name-12345"}'
```
- **Bucket names must be globally unique** across all Google Cloud projects
- Application automatically handles "already exists" errors gracefully
- For LocalStack testing, any name works (emulator doesn't enforce global uniqueness)
- Look for log messages: `Successfully created bucket:` or `Bucket 'name' already exists, continuing...`

**Missing spans:**
- Check that W3C trace propagation headers are being set in Pub/Sub messages
- Verify spans are properly nested under the root span (not separate traces)

**Spans appearing as separate traces:**
- This was fixed by using manual span creation with proper context propagation
- Ensure `AlwaysSample()` is configured to capture all spans consistently

### LocalStack Comparison

This setup mirrors LocalStack's approach for Google Cloud Platform:

| LocalStack (AWS) | This Setup (GCP) | Purpose |
|------------------|------------------|---------|
| LocalStack container | fake-gcs-server + pubsub-emulator | Service emulation |
| S3 API on :4566 | GCS API on :4443 | Object storage |
| SNS/SQS on :4566 | Pub/Sub on :8085 | Message queuing |
| Single container | Multiple containers | Architecture difference |
| AWS SDKs | Google Cloud SDKs | Client libraries |

**Advantages of this GCP setup:**
- Uses official Google Cloud emulators where available
- Better API compatibility than third-party alternatives  
- Separate containers allow independent scaling/debugging
- Native OpenTelemetry gRPC instrumentation

## Notes
- **Manual span creation**: Explicit spans ensure proper trace hierarchy and nesting
- **Always sampling**: Configured to capture all spans for complete observability  
- **W3C context propagation**: Manual injection/extraction of trace context via Pub/Sub message attributes
- **Dynamic resource creation**: API automatically creates buckets, topics, and subscriptions based on request parameters
- **Emulator auto-configuration**: When emulator endpoints are set, clients automatically use them
- **LocalStack equivalent**: fake-gcs-server + Pub/Sub emulator provide local Google Cloud development environment
- **Semantic attributes**: Spans include cloud resource IDs and messaging system metadata for better observability

## References
- OpenTelemetry Go Contrib (GCP): https://pkg.go.dev/go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc
- fake-gcs-server: https://github.com/fsouza/fake-gcs-server
- Google Cloud Pub/Sub Emulator: https://cloud.google.com/pubsub/docs/emulator