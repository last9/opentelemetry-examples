import {
  NodeTracerProvider,
  TracerConfig,
} from "@opentelemetry/sdk-trace-node";
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base"; // Use BatchSpanProcessor for better performance
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http"; // Import OTLPTraceExporter
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { SEMRESATTRS_SERVICE_NAME } from "@opentelemetry/semantic-conventions";
import { Resource } from "@opentelemetry/resources";

const providerConfig: TracerConfig = {
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: "express-api-service",
  }),
};

// Initialize and register the tracer provider
const provider = new NodeTracerProvider(providerConfig);
const otlp = new OTLPTraceExporter({
  url: process.env.OTLP_ENDPOINT,
  headers: {
    Authorization: process.env.OTLP_AUTH_HEADER,
  },
}); // Configure the OTLP exporter

provider.addSpanProcessor(new BatchSpanProcessor(otlp));
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
