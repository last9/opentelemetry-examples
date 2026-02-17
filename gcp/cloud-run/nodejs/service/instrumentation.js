'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');
const { CloudRunTracePropagator } = require('./shared/custom-propagator');

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
