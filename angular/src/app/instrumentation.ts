// Note: Run 'npm install' to resolve OpenTelemetry module imports
// This file follows the same signature as js.md but adapted for browser environment
// Configuration via environment variables (simulated through Angular environment files)

import {
  WebTracerProvider,
  ConsoleSpanExporter,
  SimpleSpanProcessor,
  BatchSpanProcessor,
} from "@opentelemetry/sdk-trace-web";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { getWebAutoInstrumentations } from "@opentelemetry/auto-instrumentations-web";
import { Resource } from "@opentelemetry/resources";
import { SemanticResourceAttributes } from "@opentelemetry/semantic-conventions";

import { environment } from '../environments/environment';

// Environment variables (browser equivalent of process.env)
const OTEL_SERVICE_NAME = environment.last9?.serviceName;
const OTEL_EXPORTER_OTLP_ENDPOINT = environment.last9?.traceEndpoint;
const OTEL_EXPORTER_OTLP_HEADERS = environment.last9?.authorizationHeader;
const OTEL_RESOURCE_ATTRIBUTES = environment.environment;
const SERVICE_VERSION = environment.serviceVersion;

// Validate required environment variables
if (!OTEL_SERVICE_NAME) {
  throw new Error('OTEL_SERVICE_NAME is required. Please set environment.last9.serviceName');
}
if (!OTEL_EXPORTER_OTLP_ENDPOINT) {
  throw new Error('OTEL_EXPORTER_OTLP_ENDPOINT is required. Please set environment.last9.traceEndpoint');
}
if (!OTEL_EXPORTER_OTLP_HEADERS) {
  throw new Error('OTEL_EXPORTER_OTLP_HEADERS is required. Please set environment.last9.authorizationHeader');
}

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: OTEL_SERVICE_NAME,
  [SemanticResourceAttributes.SERVICE_VERSION]: SERVICE_VERSION || '1.0.0',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: OTEL_RESOURCE_ATTRIBUTES || 'development',
});

const provider = new WebTracerProvider({ resource });

// Add console exporter for debugging (optional)
provider.addSpanProcessor(new SimpleSpanProcessor(new ConsoleSpanExporter()));

// Configure the OTLP exporter (following js.md signature)
const otlp = new OTLPTraceExporter({
  url: OTEL_EXPORTER_OTLP_ENDPOINT,
  headers: {
    Authorization: OTEL_EXPORTER_OTLP_HEADERS,
  },
});

provider.addSpanProcessor(new BatchSpanProcessor(otlp));

provider.register();

// Automatically instrument the Angular application
registerInstrumentations({
  instrumentations: [
    getWebAutoInstrumentations({
      // instrumentation-fs is disabled to reduce the noise of spans related to file operations
      "@opentelemetry/instrumentation-document-load": {
        enabled: true,
      },
      "@opentelemetry/instrumentation-user-interaction": {
        enabled: true,
      },
      "@opentelemetry/instrumentation-fetch": {
        propagateTraceHeaderCorsUrls: /.+/,
      },
      "@opentelemetry/instrumentation-xml-http-request": {
        propagateTraceHeaderCorsUrls: /.+/,
      },
    }),
  ],
});