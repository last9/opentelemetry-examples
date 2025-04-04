// instrumentation.js - Simplified version
const opentelemetry = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// Configuration
const LAST9_ENDPOINT = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
const LAST9_AUTH = process.env.OTEL_EXPORTER_OTLP_HEADERS;
const SERVICE_NAME = 'express-api-service';

// Simple logging utility
const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${SERVICE_NAME}`);

// Create and configure SDK
const sdk = new opentelemetry.NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: SERVICE_NAME,
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'development',
  }),
  traceExporter: new OTLPTraceExporter({
    url: LAST9_ENDPOINT,
    headers: {
      Authorization: LAST9_AUTH,
    },
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-http': { enabled: true },
      '@opentelemetry/instrumentation-express': { enabled: true },
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