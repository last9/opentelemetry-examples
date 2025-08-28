const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { resourceFromAttributes, envDetector, processDetector, hostDetector } = require('@opentelemetry/resources');
const { RuntimeNodeInstrumentation } = require('@opentelemetry/instrumentation-runtime-node');
const { PeriodicExportingMetricReader, ConsoleMetricExporter } = require('@opentelemetry/sdk-metrics');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { NodeSDK } = require('@opentelemetry/sdk-node');
// const { containerDetector } = require('@opentelemetry/resource-detector-container');
// const { awsEc2Detector, awsEcsDetector, awsLambdaDetector } = require('@opentelemetry/resource-detector-aws');
// const { gcpDetector } = require('@opentelemetry/resource-detector-gcp');
// const { azureVmDetector } = require('@opentelemetry/resource-detector-azure');

// For troubleshooting, set the log level to DiagLogLevel.DEBUG
// Uncomment the following lines to enable OpenTelemetry debug logging:
const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${process.env.OTEL_SERVICE_NAME}`);

const traceExporter = new OTLPTraceExporter();

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    'service.name': process.env.OTEL_SERVICE_NAME,
    'deployment.environment': process.env.NODE_ENV,
  }),
  spanProcessor: new BatchSpanProcessor(traceExporter),
  instrumentations: [
    getNodeAutoInstrumentations({}),
    new RuntimeNodeInstrumentation({
      monitoringPrecision: 5000,
    }),
  ],
    resourceDetectors: [
      // containerDetector,
      // awsEc2Detector,
      // awsEcsDetector,
      // awsLambdaDetector,
      // gcpDetector,
      // azureVmDetector,
      envDetector,
      processDetector,
      hostDetector
    ],
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    // For local debugging
    // exporter: new ConsoleMetricExporter(),
  }),
})

sdk.start();

logger.info('OpenTelemetry instrumentation setup complete');
logger.info('OTLP metric exporter and reader setup complete'); 