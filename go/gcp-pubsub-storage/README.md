# Instrumenting Google Cloud Storage and Pub/Sub using OpenTelemetry (Go)

This example demonstrates:
- Auto-instrumentation of Google Cloud Storage and Pub/Sub via OpenTelemetry gRPC interceptors
- End-to-end trace propagation across Pub/Sub using W3C context in message attributes
- **Trace visualization in Last9 dashboard** for comprehensive observability
- Local testing using fake-gcs-server and Pub/Sub emulator (LocalStack equivalent for Google Cloud)

It performs a Cloud Storage upload, publishes a Pub/Sub message, receives it, extracts context, and starts a consumer span. You can run it in two modes:

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

## Traces
The app creates a **hierarchical trace structure** with these spans:
- **Root span**: `gcp cloud client demo` (parent for all operations)
- **Storage span**: `upload object to GCS` (with semantic attributes)
- **Publisher span**: `publish message to Pub/Sub` (with messaging attributes)
- **Subscriber span**: `receive message from Pub/Sub` (with messaging attributes)
- **Consumer span**: `process Pub/Sub message` (linked via W3C context propagation)

All spans are properly nested under the root span, creating a single cohesive trace in Last9.

## Install dependencies
```bash
cd go/gcp-pubsub-storage
go mod tidy
```

## 🚀 Viewing Traces in Last9 

Last9 provides a comprehensive observability platform for viewing and analyzing your traces. Follow these steps:

### Step 1: Configure Last9 OTLP Endpoint
Set these environment variables before running the application:
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="Last9 OTLP Endpoint"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_RESOURCE_ATTRIBUTES="service.name=gcp-pubsub-storage-demo,deployment.environment=local"
```

### Step 2: View Traces
After running your application:
1. Open [Last9 Dashboard](https://app.last9.io)
2. Navigate to **Traces**
3. Filter by service name: `gcp-pubsub-storage-demo`
4. Explore end-to-end traces showing Storage upload → Pub/Sub publish → Pub/Sub consume workflow

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

# Run workflow with custom resource names (any names work!)
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


### Quick Start (CLI Mode with Last9)
```bash
# 1. Start local environment
docker-compose up -d

# 2. Configure environment
export STORAGE_EMULATOR_HOST=localhost:4443
export PUBSUB_EMULATOR_HOST=localhost:8085
export GOOGLE_CLOUD_PROJECT=demo-project
export GCS_BUCKET=demo-bucket
export PUBSUB_TOPIC=demo-topic  
export PUBSUB_SUBSCRIPTION=demo-subscription

# 3. Configure Last9 tracing
export OTEL_EXPORTER_OTLP_ENDPOINT="Last9 OTLP Endpoint"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_BASIC_AUTH_TOKEN>"
export OTEL_RESOURCE_ATTRIBUTES="service.name=gcp-pubsub-storage-demo,deployment.environment=local"

# 4. Run the complete workflow
go run .

# 5. View traces in Last9
# Visit https://app.last9.io > APM > Traces
# Filter by service: gcp-pubsub-storage-demo
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

✅ **Root Span**: `gcp cloud client demo` (parent span)  
├── ✅ **Storage Span**: `upload object to GCS` (with cloud resource attributes)  
├── ✅ **Publish Span**: `publish message to Pub/Sub` (with messaging attributes)  
├── ✅ **Subscribe Span**: `receive message from Pub/Sub` (with messaging attributes)  
└── ✅ **Consumer Span**: `process Pub/Sub message` (linked via W3C context)

**Key Success Indicators:**
- All spans share the **same trace ID** 
- Spans are properly **nested/hierarchical** (not separate traces)
- **Semantic attributes** are populated (resource IDs, messaging destinations)
- **End-to-end tracing** shows complete Storage → Pub/Sub → Consumer flow

### Cleanup
```bash
docker-compose down
```

## 🔧 Troubleshooting

### Common Issues

**Traces not appearing in Last9:**
- Verify `OTEL_EXPORTER_OTLP_HEADERS` is correctly Base64 encoded
- Check Last9 token has proper permissions  
- Ensure service name matches in filters: `gcp-pubsub-storage-demo`

**Emulator connection errors:**
```bash
# Verify emulators are running
docker-compose ps

# Check emulator endpoints
curl http://localhost:4443/storage/v1/  # GCS emulator
curl http://localhost:8085              # Pub/Sub emulator
```

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