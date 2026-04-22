// Must be imported before any other module
import { NodeTracerProvider } from "@opentelemetry/sdk-trace-node";
import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { LoggerProvider, BatchLogRecordProcessor } from "@opentelemetry/sdk-logs";
import { OTLPLogExporter } from "@opentelemetry/exporter-logs-otlp-http";
import { logs } from "@opentelemetry/api-logs";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { AwsInstrumentation } from "@opentelemetry/instrumentation-aws-sdk";
import { HttpInstrumentation } from "@opentelemetry/instrumentation-http";
import { resourceFromAttributes } from "@opentelemetry/resources";

const resource = resourceFromAttributes({
  "service.name": process.env.OTEL_SERVICE_NAME ?? "nestjs-sqs-subscriber",
  "deployment.environment": process.env.NODE_ENV ?? "development",
});

// Traces
const traceProvider = new NodeTracerProvider({
  resource,
  spanProcessors: [new BatchSpanProcessor(new OTLPTraceExporter())],
});
traceProvider.register();

// Logs — exports structured log records to Last9 via OTLP
// OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS are read automatically
const loggerProvider = new LoggerProvider({ resource });
loggerProvider.addLogRecordProcessor(
  new BatchLogRecordProcessor(new OTLPLogExporter()),
);
logs.setGlobalLoggerProvider(loggerProvider);

registerInstrumentations({
  instrumentations: [
    new AwsInstrumentation({
      // Extracts W3C traceparent from MessageAttributes on receive.
      // Requires MessageAttributeNames: ['All'] in ReceiveMessageCommand.
      // Set to true if producer embeds traceparent in message body JSON instead.
      sqsExtractContextPropagationFromPayload: false,
    }),
    new HttpInstrumentation(),
  ],
});
