/**
 * OpenTelemetry Instrumentation for Cloud Run
 * Must be loaded before any other modules via -r flag or import
 */
'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const {
  SEMRESATTRS_SERVICE_NAME,
  SEMRESATTRS_SERVICE_VERSION,
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
} = require('@opentelemetry/semantic-conventions');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { LoggerProvider, BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');

/**
 * Parse OTLP headers from environment variable
 * Format: "key1=value1,key2=value2"
 */
function parseHeaders(headersStr) {
  const headers = {};
  if (!headersStr) return headers;

  headersStr.split(',').forEach((pair) => {
    const [key, ...valueParts] = pair.split('=');
    if (key && valueParts.length) {
      headers[key.trim()] = valueParts.join('=').trim();
    }
  });

  return headers;
}

/**
 * Create resource with Cloud Run-specific attributes
 */
function createCloudRunResource() {
  const serviceName = process.env.OTEL_SERVICE_NAME || process.env.K_SERVICE || 'nodejs-cloud-run';

  return Resource.default().merge(
    new Resource({
      [SEMRESATTRS_SERVICE_NAME]: serviceName,
      [SEMRESATTRS_SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
      [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: process.env.DEPLOYMENT_ENVIRONMENT || 'production',
      // Cloud Run specific attributes
      'cloud.provider': 'gcp',
      'cloud.platform': 'gcp_cloud_run_revision',
      'cloud.region': process.env.CLOUD_RUN_REGION || process.env.GOOGLE_CLOUD_REGION || 'unknown',
      'cloud.account.id': process.env.GOOGLE_CLOUD_PROJECT || 'unknown',
      // FaaS attributes
      'faas.name': process.env.K_SERVICE || serviceName,
      'faas.version': process.env.K_REVISION || 'unknown',
      'faas.instance': process.env.K_REVISION || 'unknown',
      // Service instance
      'service.instance.id': process.env.K_REVISION || 'local',
    })
  );
}

// Configuration
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'https://your-otlp-endpoint';
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);
const resource = createCloudRunResource();

// Configure trace exporter
const traceExporter = new OTLPTraceExporter({
  url: `${endpoint}/v1/traces`,
  headers,
});

// Configure metric exporter
const metricExporter = new OTLPMetricExporter({
  url: `${endpoint}/v1/metrics`,
  headers,
});

// Configure log exporter
const logExporter = new OTLPLogExporter({
  url: `${endpoint}/v1/logs`,
  headers,
});

// Configure LoggerProvider with batch processor
const loggerProvider = new LoggerProvider({ resource });
loggerProvider.addLogRecordProcessor(
  new BatchLogRecordProcessor(logExporter, {
    maxExportBatchSize: 512,
    scheduledDelayMillis: 5000, // 5 second delay for cold starts
  })
);

// Initialize SDK
const sdk = new NodeSDK({
  resource,
  spanProcessor: new BatchSpanProcessor(traceExporter, {
    maxExportBatchSize: 512,
    scheduledDelayMillis: 5000, // 5 second delay for cold starts
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 60000, // Export every 60 seconds
  }),
  logRecordProcessor: new BatchLogRecordProcessor(logExporter, {
    maxExportBatchSize: 512,
    scheduledDelayMillis: 5000,
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable fs instrumentation (too noisy)
      '@opentelemetry/instrumentation-fs': { enabled: false },
      // Disable dns instrumentation
      '@opentelemetry/instrumentation-dns': { enabled: false },
      // Configure HTTP instrumentation
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/ready', '/_ah/health'],
      },
    }),
  ],
});

// Start the SDK
sdk.start();
console.log(JSON.stringify({
  severity: 'INFO',
  message: 'OpenTelemetry SDK initialized for Cloud Run',
  timestamp: new Date().toISOString(),
  service: process.env.K_SERVICE || 'local',
  revision: process.env.K_REVISION || 'local',
}));

// Graceful shutdown handlers
const shutdown = async (signal) => {
  console.log(JSON.stringify({
    severity: 'INFO',
    message: `Received ${signal}, initiating graceful shutdown`,
    timestamp: new Date().toISOString(),
  }));

  try {
    await sdk.shutdown();
    console.log(JSON.stringify({
      severity: 'INFO',
      message: 'OpenTelemetry SDK shutdown complete',
      timestamp: new Date().toISOString(),
    }));
    process.exit(0);
  } catch (error) {
    console.error(JSON.stringify({
      severity: 'ERROR',
      message: 'Error during SDK shutdown',
      timestamp: new Date().toISOString(),
      error: error.message,
    }));
    process.exit(1);
  }
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = sdk;
