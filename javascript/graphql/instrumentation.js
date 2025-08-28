import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { resourceFromAttributes } from '@opentelemetry/resources';

// import { diag, DiagConsoleLogger, DiagLogLevel, context as otContext, trace } from '@opentelemetry/api';
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG); // Change to DEBUG for troubleshooting

const providerConfig = {
  resource: resourceFromAttributes({
    'service.name': process.env.OTEL_SERVICE_NAME || 'apollo-otel-graphql-example',
    'deployment.environment': process.env.NODE_ENV || 'development',
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

const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${process.env.OTEL_SERVICE_NAME || 'apollo-otel-graphql-example'}`);
logger.info('OpenTelemetry instrumentation setup complete'); 