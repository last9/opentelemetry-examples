const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');
const api = require('@opentelemetry/api');

// For troubleshooting, uncomment the following lines to enable OpenTelemetry debug logging:
// const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

// BaggageSpanProcessor - propagates W3C Baggage entries as span attributes for RUM correlation
class BaggageSpanProcessor {
  onStart(span, parentContext) {
    const baggage = api.propagation.getBaggage(parentContext || api.context.active());
    if (!baggage) return;
    for (const [key, entry] of baggage.getAllEntries()) {
      span.setAttribute(key, entry.value);
    }
  }
  onEnd() {}
  forceFlush() { return Promise.resolve(); }
  shutdown() { return Promise.resolve(); }
}

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'sails-app',
    'deployment.environment': process.env.NODE_ENV || 'development',
  }),
  spanProcessors: [
    new BaggageSpanProcessor(),
    new BatchSpanProcessor(new OTLPTraceExporter()),
  ],
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

// sdk.start() is synchronous in sdk-node 0.201.x+
try {
  sdk.start();
  console.log('Tracing initialized');
} catch (e) {
  console.log('Error initializing tracing', e);
}

process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});

process.on('SIGINT', () => {
  sdk.shutdown().finally(() => process.exit(0));
});
