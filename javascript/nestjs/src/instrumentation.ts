import {
  NodeTracerProvider,
  TracerConfig,
} from '@opentelemetry/sdk-trace-node';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base'; // Use BatchSpanProcessor for better performance
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'; // Import OTLPTraceExporter
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import {
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
  SEMRESATTRS_SERVICE_NAME,
} from '@opentelemetry/semantic-conventions';
import { Resource } from '@opentelemetry/resources';
import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';


// Then initialize OpenTelemetry
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

const providerConfig: TracerConfig = {
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: 'nestjs-api-service',
    [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV,
  }),
};

// Initialize and register the tracer provider
const provider = new NodeTracerProvider(providerConfig);
const otlp = new OTLPTraceExporter();

// Configure OTLP exporter for Last9
const otlpExporter = new OTLPTraceExporter({
  url: process.env.LAST9_URL,
  headers: {
    'Authorization': process.env.LAST9_AUTH,
  },
});

provider.addSpanProcessor(new BatchSpanProcessor(otlp));
provider.register();

// Register auto-instrumentations
registerInstrumentations({
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': {
        enabled: false,
      },
      '@opentelemetry/instrumentation-http': {
        enabled: true,
        ignoreIncomingPaths: [/\/debug-sentry/],
      },
      '@opentelemetry/instrumentation-express': {
        enabled: true,
      },
      '@opentelemetry/instrumentation-nestjs-core': {
        enabled: true,
      },
    }),
  ],
});

console.log('OpenTelemetry Instrumentations Registered');

// Initialize Sentry after OpenTelemetry
import * as Sentry from "@sentry/nestjs";

// Initialize Sentry first
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
  profilesSampleRate: 1.0,
  environment: process.env.NODE_ENV || 'development'
});
