/**
 * OpenTelemetry Instrumentation for Node 10.x - WITHOUT GZIP FIX
 * This file is for testing - it demonstrates the EOF error without the patch
 */

'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource, envDetector, processDetector, hostDetector } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

console.log('=================================================');
console.log('Initializing OpenTelemetry for Node 10 (NO PATCH)');
console.log('OpenTelemetry Version: 0.29.2');
console.log('Node Version:', process.version);
console.log('WARNING: Gzip patch NOT applied - expect EOF errors!');
console.log('=================================================');

// Configuration
const serviceName = process.env.OTEL_SERVICE_NAME || 'node10-no-patch-test';
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'https://otlp-aps1.last9.io:443';
const headers = process.env.OTEL_EXPORTER_OTLP_HEADERS || '';

// Parse headers
const parsedHeaders = {};
if (headers) {
  headers.split(',').forEach(pair => {
    const [key, ...value] = pair.split('=');
    if (key && value.length) {
      parsedHeaders[key.trim()] = value.join('=').trim();
    }
  });
}

console.log('Service Name:', serviceName);
console.log('Endpoint:', endpoint);

// Initialize NodeSDK with gzip compression (will cause EOF errors!)
const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: serviceName,
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: endpoint.replace(/\/$/, '') + '/v1/traces',
    headers: parsedHeaders,
    compression: 'gzip',  // This will fail on 2nd+ export!
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
    }),
  ],
  resourceDetectors: [
    envDetector,
    processDetector,
    hostDetector,
  ],
});

// Start the SDK
try {
  sdk.start();
  console.log('✓ OpenTelemetry SDK started successfully');
  console.log('=================================================\n');
} catch (error) {
  console.error('✗ Failed to start OpenTelemetry SDK:', error);
  process.exit(1);
}

// Graceful shutdown
const shutdown = () => {
  console.log('\nShutting down OpenTelemetry SDK...');
  sdk.shutdown()
    .then(() => {
      console.log('✓ OpenTelemetry SDK shut down successfully');
      process.exit(0);
    })
    .catch((error) => {
      console.error('✗ Error shutting down OpenTelemetry SDK:', error);
      process.exit(1);
    });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

module.exports = sdk;
