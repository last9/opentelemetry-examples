'use strict';
console.log('=== FUNCTION OTEL LOADING ===');

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

function parseHeaders(str) {
  if (!str) return {};
  const h = {};
  str.split(',').forEach(p => {
    const [k, ...v] = p.split('=');
    if (k) h[k.trim()] = v.join('=').trim();
  });
  return h;
}

const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || '';
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);

console.log('Endpoint:', endpoint);
console.log('Service:', process.env.OTEL_SERVICE_NAME);

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'otel-api-function',
  }),
  traceExporter: new OTLPTraceExporter({
    url: `${endpoint}/v1/traces`,
    headers,
  }),
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-fs': { enabled: false },
  })],
});

sdk.start();
console.log('=== FUNCTION OTEL STARTED ===');
