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

# Test service calling function (tests custom propagator)
curl "$SERVICE_URL/chain?name=Test"

# Test function directly
FUNCTION_URL=$(gcloud functions describe my-function --region us-central1 --gen2 --format="value(serviceConfig.uri)")
curl "$FUNCTION_URL/?name=World"
```

---

## The Problem: GCP Load Balancer Span Injection

When Cloud Run services call each other (or Cloud Run Functions), GCP's load balancer modifies the W3C `traceparent` header by injecting its own span. This breaks parent-child span relationships in your traces.

### What Happens

```
┌─────────────┐
│  service-a  │  Creates CLIENT span (SpanId: abc123)
│             │  Sends traceparent: "...abc123..."
└──────┬──────┘
       │ HTTP Request
       ↓
┌──────────────────┐
│  GCP Load        │  Creates intermediate span (SpanId: xyz789)
│  Balancer        │  MODIFIES traceparent: "...xyz789..."
└────────┬─────────┘  [This span is NOT exported to Last9]
         │
         ↓
┌─────────────┐
│ service-b   │  Receives modified traceparent
│             │  Creates SERVER span with ParentSpanId: xyz789
└─────────────┘  [Parent span xyz789 doesn't exist in Last9!]
```

**Result:** The SERVER span in service-b references a parent span ID (xyz789) that was never exported to your observability platform, breaking the visual trace hierarchy.

### Why This Happens

1. **GCP Infrastructure Spans**: Cloud Run's load balancer creates spans as part of Google Cloud Trace
2. **Header Modification**: The load balancer modifies the `traceparent` header to include its own span ID
3. **Selective Export**: Your services only export to Last9 (via OTLP), not to Google Cloud Trace
4. **Missing Links**: The intermediate load balancer spans never reach Last9

### Trace Example

All spans share the same TraceId (✓), but ParentSpanId references are broken:

```json
{
  "TraceId": "5719c8b38bb1416b61c403eb50518524",  // ✓ Same for all spans
  "SpanId": "1dc99ec20ff6420c",                    // service-b SERVER span
  "ParentSpanId": "fc8c7a0328245590",              // ✗ Missing! (GCP LB span)
  "ServiceName": "service-b"
}
```

---

## The Solution: Custom Trace Propagator

This implementation uses a custom propagator that preserves the original parent context by using backup headers that GCP doesn't modify.

### How It Works

```
┌─────────────┐
│  service-a  │  1. Creates CLIENT span (SpanId: abc123)
│             │  2. Injects BOTH:
│             │     - traceparent: "...abc123..."
│             │     - x-original-traceparent: "...abc123..." (backup)
└──────┬──────┘
       │ HTTP Request (both headers)
       ↓
┌──────────────────┐
│  GCP Load        │  3. Modifies traceparent → "...xyz789..."
│  Balancer        │  4. Leaves x-original-traceparent untouched ✓
└────────┬─────────┘
         │
         ↓
┌─────────────┐
│ service-b   │  5. Extracts from x-original-traceparent FIRST
│             │  6. Gets correct parent: abc123 ✓
│             │  7. Creates SERVER span with correct ParentSpanId
└─────────────┘
```

### Implementation

The `CloudRunTracePropagator` class is included in both `service/instrumentation.js` and `functions/instrumentation.js`:

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { W3CTraceContextPropagator } = require('@opentelemetry/core');

class CloudRunTracePropagator {
  constructor() {
    this._w3cPropagator = new W3CTraceContextPropagator();
    this._backupHeader = 'x-original-traceparent';
    this._backupStateHeader = 'x-original-tracestate';
  }

  inject(context, carrier, setter) {
    // 1. Inject standard W3C headers
    this._w3cPropagator.inject(context, carrier, setter);

    // 2. Copy to backup headers (GCP won't modify these)
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
    // 1. Try backup headers first (original parent context)
    const originalTraceparent = getter.get(carrier, this._backupHeader);

    if (originalTraceparent) {
      // Found backup - use original (pre-GCP-modification) context
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

    // 2. Fallback to standard extraction
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

// Configure SDK with custom propagator
const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'cloud-run-service',
  }),
  traceExporter: new OTLPTraceExporter(),
  textMapPropagator: new CloudRunTracePropagator(), // ← Custom propagator
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

### Dependencies

The custom propagator requires `@opentelemetry/core`:

```bash
npm install --save @opentelemetry/core
```

This is already included in both `functions/package.json` and `service/package.json`.

---

## Verification

After deploying and generating traffic, verify traces in Last9:

### 1. Check Trace Hierarchy

In Last9's trace view, you should see proper parent-child relationships:

```
service-a (GET /chain)
  └─> HTTP Client (calling service-b)
       └─> service-b (GET /)
            └─> HTTP Client (calling downstream)
                 └─> downstream-service (GET /api)
```

### 2. Verify TraceId Consistency

All spans in a request chain should share the same `TraceId`:

```json
{
  "TraceId": "5719c8b38bb1416b61c403eb50518524",  // ✓ Same across all spans
  "SpanId": "1dc99ec20ff6420c",
  "ParentSpanId": "383cbbc0efd4ecdd",              // ✓ Parent exists in trace
  "ServiceName": "service-b"
}
```

### 3. Inspect Parent Span IDs

ParentSpanId values should reference spans that actually exist in the trace (not missing GCP load balancer spans).

### 4. Check Backup Headers (Optional)

You can verify the backup headers are being sent by adding a request hook:

```javascript
'@opentelemetry/instrumentation-http': {
  requestHook: (span, request) => {
    const originalTraceparent = request.headers['x-original-traceparent'];
    if (originalTraceparent) {
      span.setAttribute('http.request.x-original-traceparent', originalTraceparent);
    }
  },
}
```

---

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

# Terminal 3: Test service → function chain
curl "http://localhost:3000/chain?name=Test"
```

Check Last9 for a trace with both service and function spans properly linked.

---

## Troubleshooting

### Traces Not Appearing

1. **Check initialization logs:**
   ```bash
   gcloud run services logs read my-service --limit=50
   ```
   Look for: `"OpenTelemetry SDK initialized"`

2. **Verify environment variables:**
   ```bash
   gcloud run services describe my-service --format="value(spec.template.spec.containers[0].env)"
   ```

3. **Verify secret access:**
   ```bash
   gcloud secrets versions access latest --secret=last9-auth-header
   ```

### Broken Parent-Child Relationships

1. **Ensure all services use the custom propagator** - Both caller and callee must have `CloudRunTracePropagator` configured

2. **Check `@opentelemetry/core` is installed:**
   ```bash
   npm list @opentelemetry/core
   ```

3. **Verify both services export to the same endpoint** - Check `OTEL_EXPORTER_OTLP_ENDPOINT` matches

4. **Test locally first** - Use local testing to verify the propagator works before deploying

### Missing Function Traces

Cloud Run Functions require the `NODE_OPTIONS` environment variable:

```bash
--set-env-vars="NODE_OPTIONS=--require ./instrumentation.js"
```

Without this, the instrumentation won't load before the function framework starts.

### Cold Start Timeouts

If deployments timeout during cold starts:

```bash
gcloud run services update my-service --timeout=300
```

---

## Architecture Notes

### Why This Approach Works

1. **GCP doesn't modify custom headers** - Only standard W3C headers (`traceparent`, `tracestate`) are modified
2. **Backwards compatible** - Falls back to standard extraction if backup headers aren't present
3. **Minimal overhead** - Just copies headers, no complex logic
4. **Production tested** - This pattern is used in production Cloud Run environments

### When All Services Must Use It

The custom propagator must be used by **all services in the call chain** for parent-child relationships to work correctly:

- ✅ Service A (with propagator) → Service B (with propagator) = Correct hierarchy
- ❌ Service A (with propagator) → Service B (without propagator) = B won't extract from backup header
- ❌ Service A (without propagator) → Service B (with propagator) = A won't send backup header

### GCP Infrastructure Spans

Note that you won't see GCP load balancer spans in Last9. You'll only see your application spans with correct relationships. This is intentional - infrastructure spans aren't exported to your OTLP endpoint.

---

## Further Reading

- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)
- [Google Cloud Trace Documentation](https://cloud.google.com/trace/docs)
- [OpenTelemetry Context Propagation](https://opentelemetry.io/docs/concepts/context-propagation/)
- [OpenTelemetry HTTP Instrumentation](https://www.npmjs.com/package/@opentelemetry/instrumentation-http)
