/**
 * OpenTelemetry Instrumentation for Cloud Run (Service C)
 * Must be loaded before any other modules via require('./tracing')
 */
'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
  ATTR_DEPLOYMENT_ENVIRONMENT,
} = require('@opentelemetry/semantic-conventions');
const { W3CTraceContextPropagator } = require('@opentelemetry/core');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');

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
 * Parse OTLP headers from "key1=value1,key2=value2" format
 */
function parseHeaders(str) {
  if (!str) return {};
  const headers = {};
  str.split(',').forEach(pair => {
    const [key, ...valueParts] = pair.split('=');
    if (key && valueParts.length) {
      headers[key.trim()] = valueParts.join('=').trim();
    }
  });
  return headers;
}

// Configuration
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318';
const headers = parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS);
const serviceName = process.env.OTEL_SERVICE_NAME || 'service-c';

console.log(`[OTEL] Initializing Service C with endpoint: ${endpoint}`);

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: serviceName,
    [ATTR_SERVICE_VERSION]: process.env.K_REVISION || '1.0.0',
    [ATTR_DEPLOYMENT_ENVIRONMENT]: process.env.DEPLOYMENT_ENVIRONMENT || 'production',
    'cloud.provider': 'gcp',
    'cloud.platform': 'gcp_cloud_run',
    'cloud.region': process.env.GOOGLE_CLOUD_REGION || 'unknown',
    'cloud.account.id': process.env.GOOGLE_CLOUD_PROJECT || 'unknown',
    'service.instance.id': process.env.K_REVISION || 'local',
  }),
  spanProcessor: new BatchSpanProcessor(
    new OTLPTraceExporter({
      url: `${endpoint}/v1/traces`,
      headers,
    }),
    {
      maxExportBatchSize: 100,
      scheduledDelayMillis: 1000,
      exportTimeoutMillis: 10000,
    }
  ),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: `${endpoint}/v1/metrics`,
      headers,
    }),
    exportIntervalMillis: 30000,
  }),
  textMapPropagator: new CloudRunTracePropagator(),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingPaths: ['/health', '/ready'],
        requireParentforOutgoingSpans: false,
        requireParentforIncomingSpans: false,
        requestHook: (span, request) => {
          const traceparent = request.headers?.traceparent || request.headers?.['traceparent'];
          if (traceparent) {
            span.setAttribute('http.request.traceparent', traceparent);
          }
          const backupTraceparent = request.headers?.['x-original-traceparent'];
          if (backupTraceparent) {
            span.setAttribute('http.request.backup_traceparent', backupTraceparent);
          }
        },
        responseHook: (span, response) => {
          span.setAttribute('http.response.status_code', response.statusCode);
        },
      },
      '@opentelemetry/instrumentation-express': {
        // Ensure express routes are properly instrumented
        enabled: true,
      },
    }),
  ],
});

sdk.start();
console.log(JSON.stringify({
  severity: 'INFO',
  message: 'OpenTelemetry SDK initialized for Service C',
  timestamp: new Date().toISOString(),
  service: serviceName,
  endpoint: endpoint,
}));

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('[OTEL] Shutting down Service C SDK');
  await sdk.shutdown();
  console.log('[OTEL] Service C SDK shutdown complete');
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('[OTEL] Shutting down Service C SDK');
  await sdk.shutdown();
  console.log('[OTEL] Service C SDK shutdown complete');
  process.exit(0);
});

module.exports = { sdk };
