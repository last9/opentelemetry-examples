import * as api from "@opentelemetry/api";
import {
  NodeTracerProvider,
  TracerConfig,
} from "@opentelemetry/sdk-trace-node";
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import {
  SEMRESATTRS_SERVICE_NAME,
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
} from "@opentelemetry/semantic-conventions";
import { Resource } from "@opentelemetry/resources";

// For troubleshooting, set the log level to DiagLogLevel.DEBUG
// import { diag, DiagConsoleLogger, DiagLogLevel } from "@opentelemetry/api";
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

export const setupTracing = (serviceName: string) => {
  const providerConfig: TracerConfig = {
    resource: new Resource({
      [SEMRESATTRS_SERVICE_NAME]: serviceName,
      [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV,
    }),
  };

  // Initialize and register the tracer provider
  const provider = new NodeTracerProvider(providerConfig);
  const otlp = new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT,
    headers: {
      Authorization: process.env.OTEL_AUTHORIZATION_HEADER,
    },
  });

  provider.addSpanProcessor(new BatchSpanProcessor(otlp));

  // Automatically instrument HTTP and Koa
  registerInstrumentations({
    instrumentations: [
      getNodeAutoInstrumentations({
        "@opentelemetry/instrumentation-fs": {
          enabled: false,
        },
      }),
    ],
    tracerProvider: provider,
  });

  provider.register();

  return api.trace.getTracer(serviceName);
};
