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
const { W3CTraceContextPropagator } = require('@opentelemetry/core');
const {
  SEMRESATTRS_SERVICE_NAME,
  SEMRESATTRS_SERVICE_VERSION,
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
} = require('@opentelemetry/semantic-conventions');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');

/**
 * Custom Trace Context Propagator for GCP Cloud Run
 *
 * Preserves parent-child span relationships by using a backup header
 * that GCP infrastructure doesn't modify.
 */
class CloudRunTracePropagator {
  constructor() {
    this._w3cPropagator = new W3CTraceContextPropagator();
    this._backupHeader = 'x-original-traceparent';
    this._backupStateHeader = 'x-original-tracestate';
  }

  inject(context, carrier, setter) {
    // Inject standard W3C headers
    this._w3cPropagator.inject(context, carrier, setter);

    // Copy to backup headers (GCP won't modify these)
    const traceparent = carrier['traceparent'];
    const tracestate = carrier['tracestate'];

    if (traceparent) {
      setter.set(carrier, this._backupHeader, traceparent);
    }
    if (tracestate) {
      setter.set(carrier, this._backupStateHeader, tracestate);
    }
  }

  extract(context, carrier, getter) {
    // Try backup headers first (original parent context)
    const originalTraceparent = getter.get(carrier, this._backupHeader);

    if (originalTraceparent) {
      // Found backup header - use original (pre-GCP-modification) context
      const originalCarrier = {
        'traceparent': Array.isArray(originalTraceparent)
          ? originalTraceparent[0]
          : originalTraceparent,
      };

      const originalTracestate = getter.get(carrier, this._backupStateHeader);
      if (originalTracestate) {
        originalCarrier['tracestate'] = Array.isArray(originalTracestate)
          ? originalTracestate[0]
          : originalTracestate;
      }

      return this._w3cPropagator.extract(context, originalCarrier, {
        get: (c, key) => c[key],
        keys: (c) => Object.keys(c),
      });
    }

    // Fallback to standard extraction
    return this._w3cPropagator.extract(context, carrier, getter);
  }

  fields() {
    return [
      'traceparent',
      'tracestate',
      this._backupHeader,
      this._backupStateHeader,
    ];
  }
}

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
  // Use custom propagator for Cloud Run that preserves parent context
  // even when GCP load balancer modifies standard headers
  textMapPropagator: new CloudRunTracePropagator(),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable fs instrumentation (too noisy)
      '@opentelemetry/instrumentation-fs': { enabled: false },
      // Disable dns instrumentation
      '@opentelemetry/instrumentation-dns': { enabled: false },
      // Configure HTTP instrumentation
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/ready', '/_ah/health'],
        // Ensure we capture and propagate trace context
        requireParentforOutgoingSpans: false,
        requireParentforIncomingSpans: false,
        // Add custom request hook to log trace context
        requestHook: (span, request) => {
          const traceparent = request.headers?.traceparent || request.headers?.['traceparent'];
          if (traceparent) {
            span.setAttribute('http.request.traceparent', traceparent);
          }
        },
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
