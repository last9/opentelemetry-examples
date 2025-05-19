const opentelemetry = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME, ATTR_DEPLOYMENT_ENVIRONMENT } = require('@opentelemetry/semantic-conventions');
const FastifyOtelInstrumentation = require('@fastify/otel');
// Initialize the Fastify OpenTelemetry instrumentation. This will register the instrumentation automatically on the Fastify server.
const fastifyOtelInstrumentation = new FastifyOtelInstrumentation({ registerOnInitialization: true });

// Enable logging for OpenTelemetry if needed for debugging
// const { diag, DiagConsoleLogger, DiagLogLevel } = require("@opentelemetry/api");
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

// Simple logging utility
const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${process.env.OTEL_SERVICE_NAME}`);

// Create and configure SDK
const sdk = new opentelemetry.NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME,
    [ATTR_DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV,
  }),
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

// Initialize the SDK and register with the OpenTelemetry API
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