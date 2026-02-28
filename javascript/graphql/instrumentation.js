import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { propagation, context } from '@opentelemetry/api';
import { W3CTraceContextPropagator, W3CBaggagePropagator, CompositePropagator } from '@opentelemetry/core';

// For troubleshooting, uncomment the following lines to enable OpenTelemetry debug logging:
// import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

// BaggageSpanProcessor - propagates W3C Baggage entries as span attributes for RUM correlation
class BaggageSpanProcessor {
  onStart(span, parentContext) {
    const baggage = propagation.getBaggage(parentContext || context.active());
    if (!baggage) return;
    for (const [key, entry] of baggage.getAllEntries()) {
      span.setAttribute(key, entry.value);
    }
  }
  onEnd() {}
  forceFlush() { return Promise.resolve(); }
  shutdown() { return Promise.resolve(); }
}

const provider = new NodeTracerProvider({
  resource: resourceFromAttributes({
    'service.name': process.env.OTEL_SERVICE_NAME || 'apollo-otel-graphql-example',
    'deployment.environment': process.env.NODE_ENV || 'development',
  }),
  spanProcessors: [
    new BaggageSpanProcessor(),
    new BatchSpanProcessor(new OTLPTraceExporter()),
  ],
});

provider.register({
  propagator: new CompositePropagator({
    propagators: [new W3CTraceContextPropagator(), new W3CBaggagePropagator()],
  }),
});

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
