const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { resourceFromAttributes, envDetector, processDetector, hostDetector } = require('@opentelemetry/resources');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { NodeSDK } = require('@opentelemetry/sdk-node');

// For troubleshooting, set the log level to DiagLogLevel.DEBUG
// Uncomment the following lines to enable OpenTelemetry debug logging:
// const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'snowflake-app';
const DEPLOYMENT_ENV = process.env.NODE_ENV || 'development';

logger.info(`Initializing OpenTelemetry for service: ${SERVICE_NAME}`);

// Configure trace exporter
const traceExporter = new OTLPTraceExporter();

// Configure metrics exporter
const metricExporter = new OTLPMetricExporter();

// Configure metric reader with export interval
const metricReader = new PeriodicExportingMetricReader({
  exporter: metricExporter,
  exportIntervalMillis: 60000, // Export metrics every 60 seconds
  exportTimeoutMillis: 30000,  // Timeout for each export
});

logger.info('Metrics will be exported every 60 seconds');

// Create and configure SDK
const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    'service.name': SERVICE_NAME,
    'deployment.environment': DEPLOYMENT_ENV,
  }),
  spanProcessor: new BatchSpanProcessor(traceExporter),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
  resourceDetectors: [
    envDetector,
    processDetector,
    hostDetector
  ],
  metricReader: metricReader,
});

// Initialize the SDK and register with the OpenTelemetry API
try {
  sdk.start();
  logger.info('Tracing and Metrics initialized successfully');
} catch (error) {
  logger.error('Failed to initialize OpenTelemetry', error);
}

// Gracefully shut down the SDK on process exit
const shutdown = (signal) => {
  logger.info(`Application shutting down (${signal}), finalizing telemetry`);
  sdk.shutdown()
    .then(() => logger.info('OpenTelemetry SDK shut down successfully'))
    .catch((error) => logger.error('Error shutting down OpenTelemetry SDK', error))
    .finally(() => process.exit(0));
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

logger.info('OpenTelemetry instrumentation setup complete');
