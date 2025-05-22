const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { registerInstrumentations } = require('@opentelemetry/instrumentation');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { resourceFromAttributes } = require('@opentelemetry/resources');
// For troubleshooting, set the log level to DiagLogLevel.DEBUG
// Uncomment the following lines to enable OpenTelemetry debug logging:
const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

const providerConfig = {
  resource: resourceFromAttributes({
    'service.name': process.env.OTEL_SERVICE_NAME,
    'deployment.environment': process.env.NODE_ENV,
  }),
  spanProcessors: [
    new BatchSpanProcessor(
      new OTLPTraceExporter()
    ),
  ],
};

const provider = new NodeTracerProvider(providerConfig);
provider.register();

registerInstrumentations({
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

// Simple logging utility
const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${process.env.OTEL_SERVICE_NAME}`);

logger.info('OpenTelemetry instrumentation setup complete');