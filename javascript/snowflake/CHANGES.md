# Changes Required to Send Snowflake Metrics to Last9

This document outlines the changes needed to instrument an existing Node.js application with Snowflake to send metrics and traces to Last9.

## 1. Install Dependencies

Add the following OpenTelemetry packages to your `package.json`:

```bash
npm install @opentelemetry/api@^1.9.0 \
  @opentelemetry/auto-instrumentations-node@^0.59.0 \
  @opentelemetry/exporter-metrics-otlp-http@^0.201.1 \
  @opentelemetry/exporter-trace-otlp-http@^0.201.1 \
  @opentelemetry/instrumentation@^0.201.1 \
  @opentelemetry/resources@^2.0.1 \
  @opentelemetry/sdk-metrics@^2.0.1 \
  @opentelemetry/sdk-node@^0.201.1 \
  @opentelemetry/sdk-trace-base@^2.0.1 \
  @opentelemetry/sdk-trace-node@^2.0.1 \
  @opentelemetry/semantic-conventions@^1.34.0
```

## 2. Add Environment Variables

Add these environment variables to your `.env` file or environment configuration:

```bash
# OpenTelemetry Configuration (Required)
OTEL_SERVICE_NAME=your-service-name
OTEL_EXPORTER_OTLP_ENDPOINT=https://<your_last9_endpoint>
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your_auth_token>
```

Get your Last9 OTLP endpoint and auth token from [Last9 Dashboard](https://app.last9.io).

## 3. Create Instrumentation File

Create a new file `src/instrumentation.js`:

```javascript
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { resourceFromAttributes, envDetector, processDetector, hostDetector } = require('@opentelemetry/resources');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { NodeSDK } = require('@opentelemetry/sdk-node');

const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'snowflake-app';
const DEPLOYMENT_ENV = process.env.NODE_ENV || 'development';

const traceExporter = new OTLPTraceExporter();
const metricExporter = new OTLPMetricExporter();

const metricReader = new PeriodicExportingMetricReader({
  exporter: metricExporter,
  exportIntervalMillis: 60000,
  exportTimeoutMillis: 30000,
});

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    'service.name': SERVICE_NAME,
    'deployment.environment': DEPLOYMENT_ENV,
  }),
  spanProcessor: new BatchSpanProcessor(traceExporter),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
  resourceDetectors: [envDetector, processDetector, hostDetector],
  metricReader: metricReader,
});

sdk.start();

const shutdown = (signal) => {
  sdk.shutdown()
    .then(() => console.log('OpenTelemetry SDK shut down'))
    .finally(() => process.exit(0));
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
```

## 4. Add Custom Snowflake Metrics

Wrap your existing Snowflake query execution with metrics. Add this to your Snowflake client module:

```javascript
const { metrics, trace } = require('@opentelemetry/api');

// Create meter and metrics
const meter = metrics.getMeter('snowflake-client');

const queryCounter = meter.createCounter('snowflake.queries.total', {
  description: 'Total number of Snowflake queries executed'
});

const queryDuration = meter.createHistogram('snowflake.query.duration', {
  description: 'Duration of Snowflake queries in milliseconds',
  unit: 'ms'
});

const queryErrors = meter.createCounter('snowflake.queries.errors', {
  description: 'Total number of failed Snowflake queries'
});

const activeConnections = meter.createUpDownCounter('snowflake.connections.active', {
  description: 'Number of active Snowflake connections'
});

const rowsReturned = meter.createHistogram('snowflake.rows.returned', {
  description: 'Number of rows returned by queries'
});
```

## 5. Instrument Query Execution

Wrap your Snowflake query execution function with tracing and metrics:

```javascript
const executeQuery = (query, queryName = 'unknown') => {
  return new Promise((resolve, reject) => {
    const tracer = trace.getTracer('snowflake-client');
    const startTime = Date.now();

    tracer.startActiveSpan(`snowflake.query.${queryName}`, async (span) => {
      span.setAttribute('db.system', 'snowflake');
      span.setAttribute('db.name', connectionConfig.database);
      span.setAttribute('db.statement', query);
      span.setAttribute('query.name', queryName);

      activeConnections.add(1, { query: queryName });

      try {
        // Your existing query execution logic here
        const rows = await yourExistingQueryMethod(query);

        const duration = Date.now() - startTime;

        // Record success metrics
        queryCounter.add(1, { query: queryName, status: 'success' });
        queryDuration.record(duration, { query: queryName });
        rowsReturned.record(rows.length, { query: queryName });

        span.setAttribute('db.rows_returned', rows.length);
        span.setAttribute('db.query_duration_ms', duration);
        span.setStatus({ code: 1 });

        resolve(rows);
      } catch (err) {
        // Record error metrics
        queryErrors.add(1, { query: queryName, error: err.code || 'execution_failed' });
        span.recordException(err);
        span.setStatus({ code: 2, message: err.message });
        reject(err);
      } finally {
        activeConnections.add(-1, { query: queryName });
        span.end();
      }
    });
  });
};
```

## 6. Import Instrumentation First

In your application entry point (e.g., `server.js`, `index.js`, `app.js`), import the instrumentation file **before any other imports**:

```javascript
// MUST be the first import
require('./instrumentation');

// Then your other imports
const express = require('express');
const { executeQuery } = require('./snowflake-client');
// ... rest of your imports
```

## Summary of Files to Modify

| File | Change |
|------|--------|
| `package.json` | Add OpenTelemetry dependencies |
| `.env` | Add OTEL_* environment variables |
| `src/instrumentation.js` | Create new file for OpenTelemetry setup |
| `src/snowflake-client.js` | Add metrics and wrap query execution with tracing |
| `src/server.js` (or entry point) | Import instrumentation.js as first import |

## Metrics Collected

After implementing these changes, the following metrics will be sent to Last9:

| Metric | Type | Description |
|--------|------|-------------|
| `snowflake.queries.total` | Counter | Total queries executed |
| `snowflake.query.duration` | Histogram | Query duration in ms |
| `snowflake.queries.errors` | Counter | Failed queries |
| `snowflake.connections.active` | UpDownCounter | Active connections |
| `snowflake.rows.returned` | Histogram | Rows returned per query |

## Traces Collected

Each query will generate a span with attributes:
- `db.system`: "snowflake"
- `db.name`: Database name
- `db.statement`: SQL query
- `query.name`: Query identifier
- `db.rows_returned`: Row count
- `db.query_duration_ms`: Execution time
