# GCP Cloud Run OpenTelemetry with Custom Trace Propagator

This example demonstrates production-ready OpenTelemetry instrumentation for Google Cloud Run (2nd gen functions and services) with a **custom trace propagator** that solves the parent-child relationship problem caused by GCP's load balancer.

## The Problem

When traces cross GCP Cloud Run services/functions, the load balancer creates intermediate spans and modifies the `traceparent` header. These load balancer spans aren't exported to your observability platform (like Last9), breaking parent-child relationships and trace-to-metrics logic.

## The Solution

A custom `CloudRunTracePropagator` that:
1. Preserves the original parent context in `x-original-traceparent` header
2. Extracts from the backup header on incoming requests
3. Maintains correct span hierarchies across all services

**Status**: ✅ Implemented and ready to test

## Quick Start - End-to-End Testing

### Prerequisites

- Google Cloud SDK (`gcloud`) installed and authenticated
- Last9 account with OTLP credentials
- `jq` for JSON parsing (optional)

### 1. Get Last9 Credentials

From [Last9 Dashboard](https://app.last9.io) → Settings → OTLP Ingestion:
- OTLP Endpoint
- Authorization Header (Base64 encoded)

### 2. Deploy and Test

```bash
# Set credentials
export OTLP_ENDPOINT='https://otlp.last9.io'
export OTLP_AUTH='Authorization=Basic YOUR_BASE64_CREDENTIALS'

# Run full deployment and testing
./deploy-and-test.sh all
```

This automated script will:
1. Check prerequisites
2. Setup Last9 credentials in Secret Manager
3. Deploy function with custom propagator
4. Deploy service with custom propagator
5. Run trace propagation tests
6. Show verification steps for Last9

### 3. Verify in Last9

**Expected Result**: Traces show proper parent-child hierarchy

```
Service span (GET /chain)
  └─ HTTP client span (calling function)
     └─ Function span (helloHttp)
```

✅ All spans share the same TraceId  
✅ ParentSpanId references point to existing spans  
✅ Trace-to-metrics logic works correctly

**See**: [TESTING.md](./TESTING.md) for detailed verification steps

## What's Included

### Functions (`functions/`)
- `helloHttp` - Simple greeting function
- `processData` - Multi-step data processing pipeline
- `apiFunction` - Multi-route REST API
- `handlePubSub` - Pub/Sub event handler
- `handleStorage` - Cloud Storage event handler

### Service (`service/`)
- `GET /health` - Health check
- `GET /process` - Processing endpoint
- `GET /chain` - Calls function (tests propagator)
- `POST /multi-hop` - Multi-service chain

### Custom Propagator (`shared/`)
- `custom-propagator.js` - CloudRunTracePropagator implementation
- Preserves parent context via backup header
- Bypasses GCP load balancer modifications

## Manual Deployment

### Deploy Function

```bash
cd functions

gcloud functions deploy my-function \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=. \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --set-env-vars="OTEL_SERVICE_NAME=my-function" \
  --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### Deploy Service

```bash
cd service

# Set function URL
export FUNCTION_URL="https://your-function-url.run.app"

gcloud run deploy my-service \
  --source=. \
  --platform=managed \
  --region=us-central1 \
  --allow-unauthenticated \
  --set-env-vars="OTEL_SERVICE_NAME=my-service" \
  --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io" \
  --set-env-vars="FUNCTION_URL=${FUNCTION_URL}" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

## Directory Structure

```
gcp/cloud-run/nodejs/
├── README.md                      # This file
├── TESTING.md                     # Detailed testing guide
├── GCP_TRACE_CONTEXT.md           # Deep dive on the problem
├── deploy-and-test.sh             # Automated deployment & testing
├── functions/                     # Cloud Run Functions
│   ├── index.js                   # Function handlers
│   ├── instrumentation.js         # OTel setup (uses custom propagator)
│   ├── package.json
│   └── .env.example
├── service/                       # Cloud Run Service
│   ├── index.js                   # Express app
│   ├── instrumentation.js         # OTel setup (uses custom propagator)
│   ├── Dockerfile
│   ├── package.json
│   └── .env.example
└── shared/                        # Shared code
    └── custom-propagator.js       # CloudRunTracePropagator
```

## How It Works

### Normal W3C Trace Context (Broken)

```
┌─────────────┐
│ Service     │  Creates span, injects traceparent
└──────┬──────┘
       │ traceparent: 00-trace-ABC123-01
       ↓
┌──────────────┐
│ GCP LB      │  Modifies traceparent to point to itself
└──────┬───────┘  traceparent: 00-trace-XYZ789-01 ❌
       │
       ↓
┌─────────────┐
│ Function    │  Sees wrong parent (LB span not exported)
└─────────────┘
```

### Custom Propagator (Fixed)

```
┌─────────────┐
│ Service     │  Injects BOTH headers:
└──────┬──────┘  - traceparent (standard)
       │          - x-original-traceparent (backup) ✓
       ↓
┌──────────────┐
│ GCP LB      │  Modifies traceparent only
└──────┬───────┘  Ignores x-original-traceparent ✓
       │
       ↓
┌─────────────┐
│ Function    │  Extracts from x-original-traceparent
└─────────────┘  Correct parent! ✓
```

## Key Features

- ✅ **Custom Trace Propagator** - Preserves parent-child relationships
- ✅ **Automatic Instrumentation** - HTTP, Express, Node.js modules
- ✅ **Custom Spans** - Manual instrumentation examples
- ✅ **Structured Logging** - Trace-correlated logs
- ✅ **Custom Metrics** - Request counters and histograms
- ✅ **Cloud Run Optimized** - Serverless-friendly batch settings
- ✅ **Production Ready** - Complete error handling and shutdown

## Testing Checklist

After deploying, verify:

- [ ] Both function and service are deployed successfully
- [ ] Test requests generate traces in Last9
- [ ] Spans show proper parent-child hierarchy (not flat)
- [ ] All spans in a chain share the same TraceId
- [ ] ParentSpanId references point to existing spans
- [ ] Logs show custom propagator activity:
  - `[CloudRunPropagator] Injected backup header`
  - `[CloudRunPropagator] Found backup header`
- [ ] Last9 trace-to-metrics logic works correctly

**Detailed steps**: See [TESTING.md](./TESTING.md)

## Documentation

- **[TESTING.md](./TESTING.md)** - Complete testing guide with verification steps
- **[GCP_TRACE_CONTEXT.md](./GCP_TRACE_CONTEXT.md)** - Problem explanation and solutions
- **[functions/README.md](./functions/README.md)** - Function deployment details
- **[service/README.md](./service/README.md)** - Service deployment details

## Why This Matters

Last9's **trace-to-metrics** logic requires proper span hierarchies to:
- Calculate accurate service latencies
- Generate RED metrics (Rate, Errors, Duration) per service
- Build service dependency graphs
- Attribute latency to the correct service in the call chain

Without the custom propagator, all spans appear at the same level, breaking these features.

## Industry Context

This custom propagator approach is an **industry-standard workaround** for Cloud Run's load balancer behavior. It's used in production by teams that:
- Export traces to external observability platforms (not Google Cloud Trace)
- Need accurate cross-service trace analysis
- Depend on trace-derived metrics

## Cleanup

```bash
./deploy-and-test.sh cleanup
```

Or manually:

```bash
gcloud functions delete my-function --gen2 --region=us-central1
gcloud run services delete my-service --region=us-central1
gcloud secrets delete last9-auth-header
```

## Further Reading

- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Context Propagation](https://opentelemetry.io/docs/concepts/context-propagation/)
- [Last9 Documentation](https://last9.io/docs)
- [Google Cloud Run](https://cloud.google.com/run/docs)

---

**Questions?** See [TESTING.md](./TESTING.md) troubleshooting section or open an issue.
