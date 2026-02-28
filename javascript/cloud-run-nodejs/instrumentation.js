'use strict';

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { LoggerProvider, BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { BatchSpanProcessor, ParentBasedSampler, TraceIdRatioBasedSampler } = require('@opentelemetry/sdk-trace-base');
const { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } = require('@opentelemetry/semantic-conventions');
const api = require('@opentelemetry/api');

// For troubleshooting, uncomment the following lines to enable OpenTelemetry debug logging:
// const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

// BaggageSpanProcessor - propagates W3C Baggage entries as span attributes for RUM correlation
class BaggageSpanProcessor {
  onStart(span, parentContext) {
    const baggage = api.propagation.getBaggage(parentContext || api.context.active());
    if (!baggage) return;
    for (const [key, entry] of baggage.getAllEntries()) {
      span.setAttribute(key, entry.value);
    }
  }
  onEnd() {}
  forceFlush() { return Promise.resolve(); }
  shutdown() { return Promise.resolve(); }
}

/* ---------------- filtering processor ---------------- */

/**
 * Wraps a log processor to filter by minimum severity level.
 * Only logs at or above the specified severity are forwarded.
 *
 * Note: Once @opentelemetry/sdk-logs supports createLoggerConfigurator
 * with minimumSeverity, this can be replaced with the native solution.
 */
class FilteringLogProcessor {
  constructor(processor, minSeverity) {
    this._processor = processor;
    this._minSeverity = minSeverity;
  }

  onEmit(logRecord, context) {
    if (logRecord.severityNumber >= this._minSeverity) {
      this._processor.onEmit(logRecord, context);
    }
  }

  forceFlush() {
    return this._processor.forceFlush();
  }

  shutdown() {
    return this._processor.shutdown();
  }
}

/* ---------------- resource ---------------- */

const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'unknown-service',
  [ATTR_SERVICE_VERSION]: process.env.SERVICE_VERSION || 'dev',
  'deployment.environment': process.env.ENV || 'dev',
});

/* ---------------- logs ---------------- */

// SDK auto-reads OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS from env
const loggerProvider = new LoggerProvider({ resource });

// Filter by severity level (change as needed)
// DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21
loggerProvider.addLogRecordProcessor(
  new FilteringLogProcessor(
    new BatchLogRecordProcessor(new OTLPLogExporter()),
    SeverityNumber.INFO  // INFO and above
  )
);

// Register globally - required for logs.getLogger() to work
logs.setGlobalLoggerProvider(loggerProvider);

/* ---------------- sdk ---------------- */

const sdk = new NodeSDK({
  resource,

  sampler: new ParentBasedSampler({
    root: new TraceIdRatioBasedSampler(0.05),
  }),

  // SDK auto-reads OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS from env
  spanProcessors: [
    new BaggageSpanProcessor(),
    new BatchSpanProcessor(new OTLPTraceExporter()),
  ],

  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: 60000,
  }),

  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-http': {
        requestHook(span) {
          delete span.attributes['http.target'];
          delete span.attributes['http.route'];
          delete span.attributes['http.url'];
        },
        responseHook(span, response) {
          const code = response.statusCode;
          if (code) {
            span.attributes['http.status_class'] =
              Math.floor(code / 100) + 'xx';
          }
        },
      },
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
      '@opentelemetry/instrumentation-net': { enabled: false },
    }),
  ],
});

sdk.start();

/* ---------------- logger helpers ---------------- */

const otelLogger = logs.getLogger('app');

/**
 * INFO log
 */
function logInfo(message, attributes) {
  otelLogger.emit({
    severityText: 'INFO',
    severityNumber: SeverityNumber.INFO,
    body: message,
    attributes: attributes || {},
  });
}

/**
 * WARN log - change minimumSeverity to SeverityNumber.WARN in FilteringLogProcessor to include
 */
function logWarn(message, attributes) {
  otelLogger.emit({
    severityText: 'WARN',
    severityNumber: SeverityNumber.WARN,
    body: message,
    attributes: attributes || {},
  });
}

/**
 * ERROR log - WILL be sent
 */
function logError(message, attributes) {
  otelLogger.emit({
    severityText: 'ERROR',
    severityNumber: SeverityNumber.ERROR,
    body: message,
    attributes: attributes || {},
  });
}

/**
 * DEBUG log - change minimumSeverity to SeverityNumber.DEBUG in FilteringLogProcessor to include
 */
function logDebug(message, attributes) {
  otelLogger.emit({
    severityText: 'DEBUG',
    severityNumber: SeverityNumber.DEBUG,
    body: message,
    attributes: attributes || {},
  });
}

/* ---------------- shutdown ---------------- */

async function shutdown() {
  await loggerProvider.forceFlush().catch(() => {});
  await sdk.shutdown().catch(() => {});
}

process.on('SIGTERM', function () {
  shutdown().finally(() => process.exit(0));
});

process.on('SIGINT', function () {
  shutdown().finally(() => process.exit(0));
});

process.on('beforeExit', function () {
  shutdown();
});

process.on('uncaughtException', function (err) {
  console.error('Uncaught exception:', err);
  logError(err.message, { stack: err.stack });
  shutdown().finally(() => process.exit(1));
});

process.on('unhandledRejection', function (err) {
  console.error('Unhandled rejection:', err);
  logError(
    err && err.message ? err.message : 'Unhandled rejection',
    { stack: err && err.stack }
  );
});

/* ---------------- exports ---------------- */

module.exports = {
  otelLogger,
  logInfo,
  logWarn,
  logError,
  logDebug,
};
