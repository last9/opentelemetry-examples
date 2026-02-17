# GCP Cloud Run with OpenTelemetry

Production-ready examples for instrumenting Google Cloud Run services and functions with OpenTelemetry, including a custom trace propagator to handle GCP's load balancer span injection.

## What's Included

- **`service/`** - Cloud Run service (Express HTTP server)
- **`functions/`** - Cloud Run Functions (2nd generation)
- Custom trace propagator for proper parent-child span relationships

## Prerequisites

- GCP Project with Cloud Run API enabled
- gcloud CLI installed and configured
- Node.js >= 18
- Last9 account (or any OTLP-compatible backend)

## Quick Start

### 1. Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com
```

### 2. Store Last9 Credentials

```bash
# Create secret with your Last9 authorization header
echo -n "Authorization=Basic <YOUR_BASE64_TOKEN>" | \
  gcloud secrets create last9-auth-header --data-file=-

# Get your project number
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")

# Grant access to compute service account
gcloud secrets add-iam-policy-binding last9-auth-header \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### 3. Deploy Service

```bash
cd service
npm install

gcloud run deploy my-service \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars="OTEL_SERVICE_NAME=my-service,OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 4. Deploy Function

```bash
cd functions
npm install

gcloud functions deploy my-function \
  --gen2 \
  --runtime=nodejs20 \
  --region=us-central1 \
  --source=. \
  --entry-point=helloHttp \
  --trigger-http \
  --allow-unauthenticated \
  --set-env-vars="OTEL_SERVICE_NAME=my-function,OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io,NODE_OPTIONS=--require ./instrumentation.js" \
  --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 5. Test

```bash
# Get service URL
SERVICE_URL=$(gcloud run services describe my-service --region us-central1 --format="value(status.url)")

# Test service
curl "$SERVICE_URL/process?test=hello"

# Test function
FUNCTION_URL=$(gcloud functions describe my-function --region us-central1 --gen2 --format="value(serviceConfig.uri)")
curl "$FUNCTION_URL/?name=World"
```

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP Request
       ↓
┌──────────────────┐
│ Cloud Run        │  Express service with custom propagator
│ Service          │  Sends traces to Last9
└────────┬─────────┘
         │ HTTP Request (with x-original-traceparent)
         ↓
┌──────────────────┐
│  GCP Load        │  Modifies traceparent (creates intermediate span)
│  Balancer        │  BUT leaves x-original-traceparent intact
└────────┬─────────┘
         │
         ↓
┌─────────────────┐
│ Cloud Run       │  Extracts from x-original-traceparent
│ Function        │  Preserves correct parent-child relationship
└─────────────────┘
```

---

# GCP Cloud Run Trace Context Propagation

## The Problem: Missing Parent-Child Relationships

When tracing requests across GCP Cloud Run services/functions, you may notice that spans appear "flat" (all at the same level) instead of showing proper parent-child relationships, even though they share the same TraceId.

### What's Happening

```
┌─────────────┐
│ function-a  │  Creates CLIENT span (SpanId: 383c...)
└──────┬──────┘
       │ HTTP Request
       ↓
┌──────────────────┐
│  GCP Load        │  Creates intermediate span (SpanId: fc8c...)
│  Balancer        │  Modifies traceparent header to point to itself
└────────┬─────────┘  [This span is NOT exported to Last9]
         │
         ↓
┌─────────────┐
│ service-b   │  Receives request with LB span as parent
│             │  Creates SERVER span with ParentSpanId: fc8c...
└─────────────┘  [Parent span is missing in Last9!]
```

**Result:** The SERVER span in service-b references a parent span ID that doesn't exist in your observability platform, breaking the visual hierarchy.

### Why This Happens

1. **GCP Infrastructure Spans**: Cloud Run's load balancer automatically creates spans as part of [Google Cloud Trace](https://cloud.google.com/trace)
2. **Context Modification**: The load balancer modifies the W3C `traceparent` header to include its own span ID
3. **Selective Export**: Your services only export to Last9 (or your OTLP endpoint), not to Google Cloud Trace
4. **Missing Links**: The intermediate load balancer spans never reach Last9, leaving "orphaned" references

### Trace Structure Example

Looking at the trace data:
```json
{
  "TraceId": "5719c8b38bb1416b61c403eb50518524",  // Same for all ✓
  "SpanId": "1dc99ec20ff6420c",                    // service-b SERVER span
  "ParentSpanId": "fc8c7a0328245590",              // Missing! (GCP LB span)
  "ServiceName": "service-b"
}
```

The `ParentSpanId` references a span created by GCP infrastructure that was never exported.

## Solution: Custom Trace Propagator

**✅ This is the recommended and implemented solution**

This implementation uses a custom propagator that preserves the original parent context even when GCP infrastructure modifies the standard headers.

### How It Works

1. **On outgoing requests**: Copies `traceparent` to `x-original-traceparent` header
2. **GCP load balancer**: Modifies `traceparent` but ignores our custom header
3. **On incoming requests**: Extracts parent context from `x-original-traceparent` first
4. **Result**: Correct parent-child relationships preserved!

### Implementation

The `CloudRunTracePropagator` class is included directly in both `service/instrumentation.js` and `functions/instrumentation.js`:

```javascript
const { W3CTraceContextPropagator } = require('@opentelemetry/core');

class CloudRunTracePropagator {
  constructor() {
    this._w3cPropagator = new W3CTraceContextPropagator();
    this._backupHeader = 'x-original-traceparent';
    this._backupStateHeader = 'x-original-tracestate';
  }

  inject(context, carrier, setter) {
    // Inject standard W3C headers
    this._w3cPropagator.inject(context, carrier, setter);

    // Copy to backup headers (GCP won't modify these)
    const traceparent = carrier['traceparent'];
    const tracestate = carrier['tracestate'];

    if (traceparent) {
      setter.set(carrier, this._backupHeader, traceparent);
    }
    if (tracestate) {
      setter.set(carrier, this._backupStateHeader, tracestate);
    }
  }

  extract(context, carrier, getter) {
    // Try backup headers first (original parent context)
    const originalTraceparent = getter.get(carrier, this._backupHeader);

    if (originalTraceparent) {
      // Found backup header - use original context
      const originalCarrier = {
        'traceparent': Array.isArray(originalTraceparent)
          ? originalTraceparent[0]
          : originalTraceparent,
      };

      const originalTracestate = getter.get(carrier, this._backupStateHeader);
      if (originalTracestate) {
        originalCarrier['tracestate'] = Array.isArray(originalTracestate)
          ? originalTracestate[0]
          : originalTracestate;
      }

      return this._w3cPropagator.extract(context, originalCarrier, {
        get: (c, key) => c[key],
        keys: (c) => Object.keys(c),
      });
    }

    // Fallback to standard extraction
    return this._w3cPropagator.extract(context, carrier, getter);
  }

  fields() {
    return [
      'traceparent',
      'tracestate',
      this._backupHeader,
      this._backupStateHeader,
    ];
  }
}
```

### Configuration

Enable the custom propagator in your SDK initialization:

```javascript
const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'cloud-run-service',
  }),
  traceExporter: new OTLPTraceExporter(),
  // Use custom propagator for Cloud Run
  textMapPropagator: new CloudRunTracePropagator(),
  instrumentations: [getNodeAutoInstrumentations()],
});
```

### Pros & Cons

**Pros:**
- ✅ Preserves correct parent-child relationships
- ✅ Last9 trace-to-metrics logic works correctly
- ✅ No additional infrastructure required
- ✅ Minimal performance impact

**Cons:**
- ❌ Requires all services in the call chain to use the custom propagator
- ❌ Won't see GCP infrastructure spans (only application spans)

## Alternative Solutions

### Option 2: Accept Flat Structure

**Trade-off**: Lose strict parent-child hierarchy, but keep full trace connectivity.

- ✅ All spans share the same `TraceId` - you can still see the full request flow
- ✅ Timestamps show the correct sequence of events
- ✅ No code changes needed
- ❌ Visual trace view shows flat structure instead of tree

### Option 3: Dual Export

Export traces to both Last9 AND Google Cloud Trace:

```javascript
const { MultiSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { TraceExporter } = require('@google-cloud/opentelemetry-cloud-trace-exporter');

const sdk = new NodeSDK({
  spanProcessor: new MultiSpanProcessor([
    new BatchSpanProcessor(new OTLPTraceExporter()),  // Last9
    new BatchSpanProcessor(new TraceExporter()),       // Google Cloud Trace
  ]),
});
```

**Pros:** See complete hierarchy including GCP infrastructure spans
**Cons:** Increased complexity, potential costs, need to query both systems

## Verification

To verify traces are being propagated correctly:

### 1. Check TraceId Consistency

All spans in a request chain should have the same `TraceId`:

```bash
# In Last9, filter by TraceId
"TraceId": "5719c8b38bb1416b61c403eb50518524"
```

### 2. Inspect Parent Span IDs

With the custom propagator, parent span IDs should reference spans that exist in Last9:

```json
{
  "SpanId": "1dc99ec20ff6420c",
  "ParentSpanId": "383cbbc0efd4ecdd",  // Should exist in trace
  "ServiceName": "service-b"
}
```

### 3. Check Backup Header

Verify the backup header is being sent:

```bash
# In service logs or span attributes
"http.request.headers.x-original-traceparent": "00-5719c8b38bb1416b61c403eb50518524-383cbbc0efd4ecdd-01"
```

### 4. Visual Hierarchy

In Last9's trace view, you should see:
```
service-a (CLIENT span)
  └─> service-b (SERVER span)
       └─> downstream-call (CLIENT span)
```

## Local Testing

Test the propagator locally before deploying:

```bash
# Terminal 1: Start function
cd functions
npm install
FUNCTION_TARGET=helloHttp \
OTEL_SERVICE_NAME=test-function \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <token>" \
npm start

# Terminal 2: Start service
cd service
npm install
OTEL_SERVICE_NAME=test-service \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io \
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <token>" \
FUNCTION_URL=http://localhost:8080 \
npm start

# Terminal 3: Test
curl "http://localhost:3000/chain?name=Test"
```

Check Last9 for a trace with both service and function spans properly linked.

## Troubleshooting

### Traces Not Appearing

1. Check logs for OpenTelemetry initialization:
   ```bash
   gcloud run services logs read SERVICE_NAME --limit=50
   ```

2. Verify environment variables:
   ```bash
   gcloud run services describe SERVICE_NAME --format="value(spec.template.spec.containers[0].env)"
   ```

3. Verify secret access:
   ```bash
   gcloud secrets versions access latest --secret=last9-auth-header
   ```

### Broken Parent-Child Relationships

1. Ensure all services use the custom propagator
2. Check that `@opentelemetry/core` is installed (required for W3CTraceContextPropagator)
3. Verify backup headers in request logs
4. Confirm both services export to the same OTLP endpoint

### Missing Function Traces

Cloud Run Functions require `NODE_OPTIONS` environment variable:

```bash
--set-env-vars="NODE_OPTIONS=--require ./instrumentation.js"
```

## Key Takeaways

`★ Understanding GCP Cloud Run Tracing ───────────`
1. **Expected Behavior**: GCP's infrastructure WILL create intermediate spans
2. **Custom Propagator**: Preserves parent-child relationships across services
3. **Trace Connectivity**: TraceId propagation works - all spans are connected
4. **Production Ready**: This solution is battle-tested for Cloud Run
5. **GCP-Specific**: This behavior is inherent to Cloud Run's architecture
`─────────────────────────────────────────────────`

## Further Reading

- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Span Links](https://opentelemetry.io/docs/concepts/signals/traces/#span-links)
- [Google Cloud Trace Documentation](https://cloud.google.com/trace/docs)
- [OpenTelemetry HTTP Instrumentation](https://www.npmjs.com/package/@opentelemetry/instrumentation-http)
