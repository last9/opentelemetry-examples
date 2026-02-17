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

## Solutions & Workarounds

### Option 1: Custom Trace Propagator (✅ Recommended - Implemented)

**Industry-standard workaround for Cloud Run**

This implementation uses a custom propagator that preserves the original parent context even when GCP infrastructure modifies the standard headers.

**How it works:**
1. On outgoing requests: Copies `traceparent` to `x-original-traceparent` header
2. GCP load balancer modifies `traceparent` but ignores our custom header
3. On incoming requests: Extracts parent context from `x-original-traceparent` first
4. Result: Correct parent-child relationships preserved!

**Already configured** in `shared/custom-propagator.js` and enabled in both functions and services.

**Pros:**
- ✅ Preserves correct parent-child relationships
- ✅ Last9 trace-to-metrics logic works correctly
- ✅ No additional infrastructure required
- ✅ Minimal performance impact

**Cons:**
- ❌ Requires all services to use the custom propagator
- ❌ Won't see GCP infrastructure spans (only application spans)

### Option 2: Accept the Behavior (Fallback)

**Trade-off**: Lose strict parent-child hierarchy, but keep full trace connectivity.

- ✅ All spans share the same `TraceId` - you can still see the full request flow
- ✅ Timestamps show the correct sequence of events
- ✅ No code changes needed
- ❌ Visual trace view shows flat structure instead of tree

This is acceptable for most use cases since:
- You can filter by `TraceId` to see all related spans
- The chronological order is preserved via timestamps
- Service-to-service relationships are still visible via span attributes

### Option 2: Dual Export to Google Cloud Trace (Alternative)

Export traces to both Last9 AND Google Cloud Trace to see the complete picture.

**Pros:**
- See the full parent-child hierarchy including GCP infrastructure spans
- Understand load balancer latency

**Cons:**
- Increased complexity (managing two backends)
- Potential cost implications
- Need to query both systems for complete view

**Implementation:**
```javascript
const { MultiSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { TraceExporter } = require('@google-cloud/opentelemetry-cloud-trace-exporter');

// Export to both Last9 and Google Cloud Trace
const sdk = new NodeSDK({
  spanProcessor: new MultiSpanProcessor([
    new BatchSpanProcessor(new OTLPTraceExporter({ /* Last9 config */ })),
    new BatchSpanProcessor(new TraceExporter()),  // Google Cloud Trace
  ]),
  // ... rest of config
});
```

### Option 3: Use Span Links

Instead of relying on parent-child relationships, use [Span Links](https://opentelemetry.io/docs/concepts/signals/traces/#span-links) to explicitly connect related spans.

**Pros:**
- Works across any infrastructure
- More flexible than strict parent-child

**Cons:**
- Requires custom instrumentation
- Not automatically visualized in all UIs

**Implementation:**
```javascript
const { trace, context } = require('@opentelemetry/api');

// In your service making the outbound call
app.post('/', async (req, res) => {
  const currentSpan = trace.getActiveSpan();
  const spanContext = currentSpan.spanContext();

  // Make HTTP call (traceparent is automatically propagated)
  const response = await axios.post(nextServiceUrl, data, {
    headers: {
      // Add custom header with original span for linking
      'x-original-span': JSON.stringify({
        traceId: spanContext.traceId,
        spanId: spanContext.spanId,
      }),
    },
  });
});

// In the receiving service
const { trace } = require('@opentelemetry/api');

app.post('/', (req, res) => {
  const originalSpanData = JSON.parse(req.headers['x-original-span'] || '{}');

  if (originalSpanData.traceId) {
    const span = trace.getActiveSpan();
    // Add link to the original calling span
    span.addLink({
      context: {
        traceId: originalSpanData.traceId,
        spanId: originalSpanData.spanId,
        traceFlags: 1,
      },
    });
  }

  // Handle request
});
```

### Option 4: Configure HTTP Instrumentation

The updated `instrumentation.js` files now include:

```javascript
'@opentelemetry/instrumentation-http': {
  // Allow spans even without immediate parent
  requireParentforOutgoingSpans: false,
  requireParentforIncomingSpans: false,
  // Log the traceparent header for debugging
  requestHook: (span, request) => {
    const traceparent = request.headers?.traceparent;
    if (traceparent) {
      span.setAttribute('http.request.traceparent', traceparent);
    }
  },
}
```

This helps by:
- Capturing the `traceparent` header as a span attribute for debugging
- Ensuring spans are created even when parent context is unclear

## Verification

To verify traces are being propagated correctly (even if parent-child is broken):

1. **Check TraceId consistency**: All spans in a request chain should have the same `TraceId`
   ```bash
   # Look for this in your trace data
   "TraceId": "5719c8b38bb1416b61c403eb50518524"
   ```

2. **Inspect traceparent attribute**: Check if it's being captured
   ```json
   {
     "SpanAttributes": {
       "http.request.traceparent": "00-5719c8b38bb1416b61c403eb50518524-383cbbc0efd4ecdd-01"
     }
   }
   ```

3. **Verify timing**: Parent spans should start before child spans
   - function-a CLIENT span: starts at T
   - service-b SERVER span: starts at T + network latency

## Key Takeaways

`★ Understanding GCP Cloud Run Tracing ───────────`
1. **Expected Behavior**: GCP's infrastructure WILL create intermediate spans
2. **Trace Connectivity**: TraceId propagation works perfectly - all spans are connected
3. **Visual Limitation**: Parent-child hierarchy may appear broken in UI
4. **Production Ready**: This doesn't affect trace completeness or debugging capability
5. **GCP-Specific**: This behavior is inherent to Cloud Run's architecture
`─────────────────────────────────────────────────`

## Further Reading

- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Span Links](https://opentelemetry.io/docs/concepts/signals/traces/#span-links)
- [Google Cloud Trace Documentation](https://cloud.google.com/trace/docs)
- [OpenTelemetry HTTP Instrumentation](https://www.npmjs.com/package/@opentelemetry/instrumentation-http)
