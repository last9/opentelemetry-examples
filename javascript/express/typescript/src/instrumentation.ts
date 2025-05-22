import {
  NodeTracerProvider,
  TracerConfig,
} from "@opentelemetry/sdk-trace-node";
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base"; // Use BatchSpanProcessor for better performance
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http"; // Import OTLPTraceExporter
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { resourceFromAttributes } from "@opentelemetry/resources";
// import { diag, DiagConsoleLogger, DiagLogLevel } from "@opentelemetry/api";

// For troubleshooting, set the log level to DiagLogLevel.DEBUG
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

const providerConfig: TracerConfig = {
  resource: resourceFromAttributes({
    ["service.name"]: process.env.OTEL_SERVICE_NAME,
    ["deployment.environment"]: process.env.NODE_ENV,
  }),
  spanProcessors: [
    new BatchSpanProcessor(
      new OTLPTraceExporter({
        url: process.env.OTLP_ENDPOINT,
      })
    ),
  ],
};

// Initialize and register the tracer provider
const provider = new NodeTracerProvider(providerConfig);
provider.register();

// Automatically instrument HTTP and Express (additional instrumentations can be added similarly)
registerInstrumentations({
  instrumentations: [
    getNodeAutoInstrumentations({
      // instrumentation-fs is disabled to reduce the noise of spans related to file operations
      "@opentelemetry/instrumentation-fs": {
        enabled: false,
      },
    }),
  ],
});
