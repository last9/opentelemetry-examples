/**
 * OpenTelemetry Instrumentation for Node 14.x
 * Uses OpenTelemetry JS SDK 1.x (v0.52.1)
 *
 * This file MUST be loaded before any other modules using: node -r ./instrumentation.js app.js
 *
 * Features:
 * - Auto-instrumentation for HTTP, Express, databases, etc.
 * - Resource detectors (AWS, Container, Host, Process, Env)
 * - Runtime metrics (CPU, memory, event loop)
 * - OTLP trace and metric export to Last9
 */

'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { Resource, envDetector, processDetector, hostDetector } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');
const {
  BatchSpanProcessor,
  TraceIdRatioBasedSampler,
  ParentBasedSampler,
  AlwaysOnSampler,
  AlwaysOffSampler
} = require('@opentelemetry/sdk-trace-node');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { RuntimeNodeInstrumentation } = require('@opentelemetry/instrumentation-runtime-node');
const { containerDetector } = require('@opentelemetry/resource-detector-container');
const { awsEc2Detector, awsEcsDetector, awsLambdaDetector } = require('@opentelemetry/resource-detector-aws');
// Optional: Uncomment if running on GCP or Azure
// const { gcpDetector } = require('@opentelemetry/resource-detector-gcp');
// const { azureVmDetector } = require('@opentelemetry/resource-detector-azure');

// For troubleshooting, uncomment to enable debug logging:
// const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

console.log('=================================================');
console.log('Initializing OpenTelemetry for Node 14');
console.log('Node Version:', process.version);
console.log('OpenTelemetry SDK: 0.52.1');
console.log('=================================================');

const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

// Configuration from environment variables
const serviceName = process.env.OTEL_SERVICE_NAME || 'node14-express-example';
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
const headers = process.env.OTEL_EXPORTER_OTLP_HEADERS || '';
const resourceAttrs = process.env.OTEL_RESOURCE_ATTRIBUTES || 'deployment.environment=local';

// Parse headers (format: "key1=value1,key2=value2")
const parsedHeaders = {};
if (headers) {
  headers.split(',').forEach(pair => {
    const [key, ...value] = pair.split('=');
    if (key && value.length) {
      parsedHeaders[key.trim()] = value.join('=').trim();
    }
  });
}

// Parse resource attributes
const parsedResourceAttrs = {};
if (resourceAttrs) {
  resourceAttrs.split(',').forEach(pair => {
    const [key, ...value] = pair.split('=');
    if (key && value.length) {
      parsedResourceAttrs[key.trim()] = value.join('=').trim();
    }
  });
}

/**
 * Create a sampler based on environment variables.
 * Supports standard OpenTelemetry sampler configuration:
 * - OTEL_TRACES_SAMPLER: Sampler type (always_on, always_off, traceidratio, parentbased_*)
 * - OTEL_TRACES_SAMPLER_ARG: Sampling ratio for ratio-based samplers (0.0 to 1.0)
 */
function createSampler() {
  const samplerType = process.env.OTEL_TRACES_SAMPLER || 'parentbased_traceidratio';
  const ratio = parseFloat(process.env.OTEL_TRACES_SAMPLER_ARG || '1.0');

  switch (samplerType) {
    case 'always_on':
      return new AlwaysOnSampler();
    case 'always_off':
      return new AlwaysOffSampler();
    case 'traceidratio':
      return new TraceIdRatioBasedSampler(ratio);
    case 'parentbased_always_on':
      return new ParentBasedSampler({ root: new AlwaysOnSampler() });
    case 'parentbased_always_off':
      return new ParentBasedSampler({ root: new AlwaysOffSampler() });
    case 'parentbased_traceidratio':
    default:
      return new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(ratio) });
  }
}

logger.info(`Initializing for service: ${serviceName}`);
console.log('Service Name:', serviceName);
console.log('Endpoint:', endpoint);
console.log('Resource Attributes:', parsedResourceAttrs);
console.log('Sampler:', process.env.OTEL_TRACES_SAMPLER || 'parentbased_traceidratio');
console.log('Sampling Ratio:', process.env.OTEL_TRACES_SAMPLER_ARG || '1.0');

// Configure OTLP trace exporter
const traceExporter = new OTLPTraceExporter({
  url: endpoint.replace(/\/$/, '') + '/v1/traces',
  headers: parsedHeaders,
});

// Configure OTLP metric exporter
const metricExporter = new OTLPMetricExporter({
  url: endpoint.replace(/\/$/, '') + '/v1/metrics',
  headers: parsedHeaders,
});

// Initialize the SDK with resource detectors, metrics, and runtime instrumentation
const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: serviceName,
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
    'node.version': process.version,
    'otel.sdk.version': '0.52.1',
    ...parsedResourceAttrs,
  }),
  sampler: createSampler(),
  spanProcessors: [new BatchSpanProcessor(traceExporter)],
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable noisy instrumentations
      '@opentelemetry/instrumentation-fs': {
        enabled: false,
      },
      '@opentelemetry/instrumentation-dns': {
        enabled: false,
      },
    }),
    // Runtime metrics instrumentation
    // Collects CPU usage, memory, event loop lag, active handles/requests
    new RuntimeNodeInstrumentation({
      monitoringPrecision: 5000, // Collect metrics every 5 seconds
    }),
  ],
  // Resource detectors automatically detect environment metadata
  resourceDetectors: [
    containerDetector,      // Detects Docker/container info
    awsEc2Detector,        // Detects AWS EC2 instance info
    awsEcsDetector,        // Detects AWS ECS/Fargate info
    // awsLambdaDetector,  // Detects AWS Lambda info (uncomment if running in Lambda)
    // gcpDetector,        // Detects GCP info (requires @opentelemetry/resource-detector-gcp)
    // azureVmDetector,    // Detects Azure VM info (requires @opentelemetry/resource-detector-azure)
    envDetector,           // Detects info from OTEL_RESOURCE_ATTRIBUTES env var
    processDetector,       // Detects process info (PID, command, runtime)
    hostDetector           // Detects host info (hostname, architecture)
  ],
  // Metrics reader exports metrics periodically
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 60000, // Export metrics every 60 seconds
  }),
});

// Start the SDK
try {
  sdk.start();
  console.log('✓ OpenTelemetry SDK started successfully');
  console.log('✓ Auto-instrumentation enabled for:');
  console.log('  - HTTP/HTTPS');
  console.log('  - Express');
  console.log('  - Database drivers (pg, mysql, mongodb, redis)');
  console.log('  - gRPC, Kafka, and more...');
  console.log('✓ Runtime metrics enabled:');
  console.log('  - CPU usage');
  console.log('  - Memory usage (heap, RSS)');
  console.log('  - Event loop lag');
  console.log('  - Active handles/requests');
  console.log('✓ Resource detectors enabled:');
  console.log('  - Container/Docker detection');
  console.log('  - AWS EC2/ECS detection');
  console.log('  - Host and process detection');
  console.log('✓ Sampling configured:');
  console.log(`  - Sampler: ${process.env.OTEL_TRACES_SAMPLER || 'parentbased_traceidratio'}`);
  console.log(`  - Ratio: ${process.env.OTEL_TRACES_SAMPLER_ARG || '1.0'}`);
  console.log('✓ Metrics export interval: 60 seconds');
  console.log('=================================================\n');

  logger.info('OpenTelemetry instrumentation setup complete');
  logger.info('OTLP metric exporter and reader setup complete');
} catch (error) {
  logger.error('Failed to start OpenTelemetry SDK', error);
  process.exit(1);
}

// Graceful shutdown
const shutdown = () => {
  logger.info('SIGTERM/SIGINT received, shutting down OpenTelemetry SDK...');
  sdk.shutdown()
    .then(() => {
      logger.info('OpenTelemetry SDK shut down successfully');
      process.exit(0);
    })
    .catch((error) => {
      logger.error('Error shutting down OpenTelemetry SDK', error);
      process.exit(1);
    });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

module.exports = sdk;
