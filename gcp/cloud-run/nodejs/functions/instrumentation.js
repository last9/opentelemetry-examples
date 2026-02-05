/**
 * OpenTelemetry Instrumentation for Cloud Run Functions
 * Must be loaded before any other modules via -r flag
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
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');

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
 * Create resource with Cloud Run Functions-specific attributes
 */
function createCloudRunFunctionsResource() {
  // FUNCTION_TARGET is set by the Functions Framework
  const functionName = process.env.FUNCTION_TARGET || process.env.K_SERVICE || 'unknown-function';
  const serviceName = process.env.OTEL_SERVICE_NAME || functionName;

  return Resource.default().merge(
    new Resource({
      [SEMRESATTRS_SERVICE_NAME]: serviceName,
      [SEMRESATTRS_SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
      [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: process.env.DEPLOYMENT_ENVIRONMENT || 'production',
      // Cloud provider attributes
      'cloud.provider': 'gcp',
      'cloud.platform': 'gcp_cloud_run_revision',
      'cloud.region': process.env.FUNCTION_REGION || process.env.GOOGLE_CLOUD_REGION || 'unknown',
      'cloud.account.id': process.env.GOOGLE_CLOUD_PROJECT || 'unknown',
      // FaaS (Function as a Service) attributes
      'faas.name': functionName,
      'faas.version': process.env.K_REVISION || 'unknown',
      'faas.instance': process.env.K_REVISION || 'local',
      'faas.max_memory': process.env.FUNCTION_MEMORY_MB ? `${process.env.FUNCTION_MEMORY_MB}Mi` : 'unknown',
      // Cloud Run specific (Functions 2nd gen runs on Cloud Run)
      'service.instance.id': process.env.K_REVISION || 'local',
    })
  );
}

// Configuration
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'https://your-otlp-endpoint';
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);
const resource = createCloudRunFunctionsResource();

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

// Initialize SDK with settings optimized for serverless
const sdk = new NodeSDK({
  resource,
  spanProcessor: new BatchSpanProcessor(traceExporter, {
    maxExportBatchSize: 100,
    // Shorter delay for functions (they may terminate quickly)
    scheduledDelayMillis: 1000,
    // Export before timeout
    exportTimeoutMillis: 10000,
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    // More frequent exports for short-lived functions
    exportIntervalMillis: 30000,
  }),
  logRecordProcessor: new BatchLogRecordProcessor(logExporter, {
    maxExportBatchSize: 100,
    scheduledDelayMillis: 1000,
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
  message: 'OpenTelemetry SDK initialized for Cloud Run Functions',
  timestamp: new Date().toISOString(),
  function: process.env.FUNCTION_TARGET || 'unknown',
  service: process.env.K_SERVICE || 'local',
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
  } catch (error) {
    console.error(JSON.stringify({
      severity: 'ERROR',
      message: 'Error during SDK shutdown',
      timestamp: new Date().toISOString(),
      error: error.message,
    }));
  }
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = { sdk };
