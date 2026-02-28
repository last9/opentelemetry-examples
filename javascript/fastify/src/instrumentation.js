const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');
const api = require('@opentelemetry/api');
const FastifyOtelInstrumentation = require('@fastify/otel');
// Initialize the Fastify OpenTelemetry instrumentation. This will register the instrumentation automatically on the Fastify server.
const fastifyOtelInstrumentation = new FastifyOtelInstrumentation({ registerOnInitialization: true });

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

// Simple logging utility
const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${process.env.OTEL_SERVICE_NAME}`);

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME,
    'deployment.environment': process.env.NODE_ENV,
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

// Initialize the SDK and register with the OpenTelemetry API
// sdk.start() is synchronous in sdk-node 0.201.x+
try {
  sdk.start();
  logger.info('Tracing initialized successfully');
} catch (error) {
  logger.error('Failed to initialize tracing', error);
}

// Gracefully shut down the SDK on process exit
process.on('SIGTERM', () => {
  logger.info('Application shutting down, finalizing traces');
  sdk.shutdown()
    .then(() => logger.info('Trace provider shut down successfully'))
    .catch((error) => logger.error('Error shutting down trace provider', error))
    .finally(() => process.exit(0));
});

process.on('SIGINT', () => {
  logger.info('Application shutting down (SIGINT), finalizing traces');
  sdk.shutdown()
    .then(() => logger.info('Trace provider shut down successfully'))
    .catch((error) => logger.error('Error shutting down trace provider', error))
    .finally(() => process.exit(0));
});

logger.info('OpenTelemetry instrumentation setup complete');
