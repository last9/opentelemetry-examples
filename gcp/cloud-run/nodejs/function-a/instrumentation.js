/**
 * OpenTelemetry Instrumentation for Cloud Run Functions (Function A)
 * Must be loaded before any other modules via require('./instrumentation')
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
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
  ATTR_DEPLOYMENT_ENVIRONMENT,
} = require('@opentelemetry/semantic-conventions');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');

/**
 * Custom Trace Context Propagator for GCP Cloud Run
 * Preserves parent-child span relationships using backup headers
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
  const functionName = process.env.FUNCTION_TARGET || process.env.K_SERVICE || 'function-a';
  const serviceName = process.env.OTEL_SERVICE_NAME || functionName;

  return Resource.default().merge(
    new Resource({
      [ATTR_SERVICE_NAME]: serviceName,
      [ATTR_SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
      [ATTR_DEPLOYMENT_ENVIRONMENT]: process.env.DEPLOYMENT_ENVIRONMENT || 'production',
      // Cloud provider attributes
      'cloud.provider': 'gcp',
      'cloud.platform': 'gcp_cloud_run_revision',
      'cloud.region': process.env.FUNCTION_REGION || process.env.GOOGLE_CLOUD_REGION || 'unknown',
      'cloud.account.id': process.env.GOOGLE_CLOUD_PROJECT || 'unknown',
      // FaaS attributes
      'faas.name': functionName,
      'faas.version': process.env.K_REVISION || 'unknown',
      'faas.instance': process.env.K_REVISION || 'local',
      'faas.max_memory': process.env.FUNCTION_MEMORY_MB ? `${process.env.FUNCTION_MEMORY_MB}Mi` : 'unknown',
      // Cloud Run specific
      'service.instance.id': process.env.K_REVISION || 'local',
    })
  );
}

// Configuration
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318';
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);
const serviceName = process.env.OTEL_SERVICE_NAME || process.env.FUNCTION_TARGET || process.env.K_SERVICE || 'function-a';
const resource = createCloudRunFunctionsResource();

console.log(`[OTEL] Initializing Function A with endpoint: ${endpoint}`);

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
    scheduledDelayMillis: 1000,
    exportTimeoutMillis: 10000,
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 30000,
  }),
  logRecordProcessor: new BatchLogRecordProcessor(logExporter, {
    maxExportBatchSize: 100,
    scheduledDelayMillis: 1000,
  }),
  textMapPropagator: new CloudRunTracePropagator(),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/ready', '/_ah/health'],
        requireParentforOutgoingSpans: false,
        requireParentforIncomingSpans: false,
        requestHook: (span, request) => {
          const traceparent = request.headers?.traceparent || request.headers?.['traceparent'];
          if (traceparent) {
            span.setAttribute('http.request.traceparent', traceparent);
          }
        },
        responseHook: (span, response) => {
          span.setAttribute('http.response.status_code', response.statusCode);
        },
      },
    }),
  ],
});

// Start the SDK
sdk.start();
console.log(JSON.stringify({
  severity: 'INFO',
  message: 'OpenTelemetry SDK initialized for Function A',
  timestamp: new Date().toISOString(),
  function: process.env.FUNCTION_TARGET || 'unknown',
  service: serviceName,
  endpoint: endpoint,
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
