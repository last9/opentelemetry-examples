'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');
const { W3CTraceContextPropagator } = require('@opentelemetry/core');

/**
 * Custom Trace Context Propagator for GCP Cloud Run
 *
 * Preserves parent-child span relationships by using a backup header
 * that GCP infrastructure doesn't modify.
 */
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
      // Found backup header - use original (pre-GCP-modification) context
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

/**
 * Parse OTLP headers from "key1=value1,key2=value2" format
 */
function parseHeaders(str) {
  if (!str) return {};
  const headers = {};
  str.split(',').forEach(pair => {
    const [key, ...valueParts] = pair.split('=');
    if (key && valueParts.length) {
      headers[key.trim()] = valueParts.join('=').trim();
    }
  });
  return headers;
}

const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || '';
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'cloud-run-service',
    'service.version': process.env.K_REVISION || '1.0.0',
    'cloud.provider': 'gcp',
    'cloud.platform': 'gcp_cloud_run',
  }),
  traceExporter: new OTLPTraceExporter({
    url: `${endpoint}/v1/traces`,
    headers,
  }),
  // Use custom propagator for Cloud Run that preserves parent context
  // even when GCP load balancer modifies standard headers
  textMapPropagator: new CloudRunTracePropagator(),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
      // Configure HTTP instrumentation for better context propagation
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/ready'],
        // Ensure we capture and propagate trace context
        requireParentforOutgoingSpans: false,
        requireParentforIncomingSpans: false,
        // Add custom request hook to log trace context
        requestHook: (span, request) => {
          // Log the traceparent header being received
          const traceparent = request.headers?.traceparent || request.headers?.['traceparent'];
          if (traceparent) {
            span.setAttribute('http.request.traceparent', traceparent);
          }
        },
      },
    }),
  ],
});

sdk.start();
console.log('OpenTelemetry SDK initialized');

// Graceful shutdown
process.on('SIGTERM', async () => {
  await sdk.shutdown();
  process.exit(0);
});
