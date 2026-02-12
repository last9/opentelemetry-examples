# Snowflake Node.js Integration with OpenTelemetry

Send Snowflake query metrics and traces from your Node.js application to Last9 using OpenTelemetry.

## Overview

This integration enables you to monitor Snowflake database operations from your Node.js applications by collecting:

- **Traces**: Distributed tracing for every Snowflake query with full context propagation
- **Metrics**: Query performance, error rates, connection pool health, and throughput

Since Snowflake doesn't have native OpenTelemetry auto-instrumentation, this guide shows you how to implement manual instrumentation following [OpenTelemetry semantic conventions for database spans](https://opentelemetry.io/docs/specs/semconv/database/database-spans/).

## Prerequisites

- Node.js v18, v20, or v22
- Existing Node.js application using [snowflake-sdk](https://www.npmjs.com/package/snowflake-sdk)
- Snowflake account with valid credentials
- [Last9 account](https://app.last9.io) for OTLP endpoint and authentication

## Quick Start

### Step 1: Install OpenTelemetry Dependencies

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

### Step 2: Configure Environment Variables

Add the following environment variables to your application:

```bash
# OpenTelemetry Configuration
OTEL_SERVICE_NAME=your-snowflake-app
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <YOUR_LAST9_AUTH_TOKEN>

# Snowflake Configuration
SNOWFLAKE_ACCOUNT=your_account.region.aws
SNOWFLAKE_USER=your_username
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_DATABASE=your_database
SNOWFLAKE_SCHEMA=your_schema
```

Get your Last9 OTLP endpoint and auth token from the [Last9 Dashboard](https://app.last9.io) under **Integrations > OpenTelemetry**.

### Step 3: Create the Instrumentation File

Create `src/instrumentation.js` to initialize OpenTelemetry. This file **must be imported before any other modules** in your application.

```javascript
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const {
  resourceFromAttributes,
  envDetector,
  processDetector,
  hostDetector
} = require('@opentelemetry/resources');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { NodeSDK } = require('@opentelemetry/sdk-node');

const SERVICE_NAME = process.env.OTEL_SERVICE_NAME || 'snowflake-app';
const DEPLOYMENT_ENV = process.env.NODE_ENV || 'development';

// Configure exporters
const traceExporter = new OTLPTraceExporter();
const metricExporter = new OTLPMetricExporter();

// Configure metric reader with 60-second export interval
const metricReader = new PeriodicExportingMetricReader({
  exporter: metricExporter,
  exportIntervalMillis: 60000,
  exportTimeoutMillis: 30000,
});

// Initialize the OpenTelemetry SDK
const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    'service.name': SERVICE_NAME,
    'deployment.environment': DEPLOYMENT_ENV,
  }),
  spanProcessor: new BatchSpanProcessor(traceExporter),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable fs instrumentation to reduce noise
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
  resourceDetectors: [envDetector, processDetector, hostDetector],
  metricReader: metricReader,
});

sdk.start();

// Graceful shutdown
const shutdown = (signal) => {
  sdk.shutdown()
    .then(() => console.log('OpenTelemetry SDK shut down'))
    .finally(() => process.exit(0));
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
```

### Step 4: Add Snowflake Metrics

Create or update your Snowflake client module to include custom metrics. The following metrics follow OpenTelemetry semantic conventions:

```javascript
const snowflake = require('snowflake-sdk');
const { metrics, trace } = require('@opentelemetry/api');

// Initialize meter for Snowflake metrics
const meter = metrics.getMeter('snowflake-client');

// Define custom metrics
const queryCounter = meter.createCounter('snowflake.queries.total', {
  description: 'Total number of Snowflake queries executed',
});

const queryDuration = meter.createHistogram('snowflake.query.duration', {
  description: 'Duration of Snowflake queries in milliseconds',
  unit: 'ms',
});

const queryErrors = meter.createCounter('snowflake.queries.errors', {
  description: 'Total number of failed Snowflake queries',
});

const activeConnections = meter.createUpDownCounter('snowflake.connections.active', {
  description: 'Number of active Snowflake connections',
});

const rowsReturned = meter.createHistogram('snowflake.rows.returned', {
  description: 'Number of rows returned by queries',
});
```

### Step 5: Instrument Query Execution

Wrap your Snowflake query execution with tracing spans and metric recording:

```javascript
const executeQuery = (query, queryName = 'unknown') => {
  return new Promise((resolve, reject) => {
    const tracer = trace.getTracer('snowflake-client');
    const startTime = Date.now();

    tracer.startActiveSpan(`snowflake.query.${queryName}`, async (span) => {
      // Set span attributes following OTel database semantic conventions
      span.setAttribute('db.system', 'snowflake');
      span.setAttribute('db.name', process.env.SNOWFLAKE_DATABASE);
      span.setAttribute('db.statement', query);
      span.setAttribute('db.operation.name', queryName);
      span.setAttribute('server.address', process.env.SNOWFLAKE_ACCOUNT);

      activeConnections.add(1, { query: queryName });

      try {
        // Execute your Snowflake query here
        const rows = await executeSnowflakeQuery(query);

        const duration = Date.now() - startTime;

        // Record success metrics
        queryCounter.add(1, { query: queryName, status: 'success' });
        queryDuration.record(duration, { query: queryName });
        rowsReturned.record(rows.length, { query: queryName });

        // Set span attributes for successful query
        span.setAttribute('db.rows_returned', rows.length);
        span.setAttribute('db.query_duration_ms', duration);
        span.setStatus({ code: 1 }); // OK

        resolve(rows);
      } catch (err) {
        // Record error metrics
        queryErrors.add(1, {
          query: queryName,
          error: err.code || 'execution_failed'
        });

        // Record exception on span
        span.recordException(err);
        span.setStatus({ code: 2, message: err.message }); // ERROR

        reject(err);
      } finally {
        activeConnections.add(-1, { query: queryName });
        span.end();
      }
    });
  });
};
```

### Step 6: Update Application Entry Point

In your application entry point (e.g., `server.js`, `index.js`, or `app.js`), import the instrumentation file **as the very first import**:

```javascript
// CRITICAL: Must be the first import
require('./instrumentation');

// Then import other modules
const express = require('express');
const { executeQuery } = require('./snowflake-client');
// ... rest of your imports
```

## Telemetry Reference

### Traces

Each Snowflake query generates a span with the following attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `db.system` | string | Always `snowflake` |
| `db.name` | string | Snowflake database name |
| `db.statement` | string | SQL query text |
| `db.operation.name` | string | Query identifier/name |
| `db.rows_returned` | int | Number of rows returned |
| `db.query_duration_ms` | int | Query execution time in ms |
| `server.address` | string | Snowflake account identifier |

### Metrics

| Metric | Type | Unit | Description |
|--------|------|------|-------------|
| `snowflake.queries.total` | Counter | count | Total queries executed |
| `snowflake.query.duration` | Histogram | ms | Query execution duration |
| `snowflake.queries.errors` | Counter | count | Failed query count |
| `snowflake.connections.active` | UpDownCounter | count | Current active connections |
| `snowflake.rows.returned` | Histogram | count | Rows returned per query |

### Metric Attributes

All metrics include the following attributes:

| Attribute | Description |
|-----------|-------------|
| `query` | Query name/identifier |
| `status` | `success` or `error` (for counters) |
| `error` | Error code (for error counter) |

## Connection Pool Configuration

For production environments, configure the Snowflake connection pool:

```javascript
const poolOptions = {
  max: parseInt(process.env.SNOWFLAKE_POOL_MAX || '10', 10),
  min: parseInt(process.env.SNOWFLAKE_POOL_MIN || '2', 10),
  acquireTimeoutMillis: 30000,
  idleTimeoutMillis: 300000,
};

const snowflakePool = snowflake.createPool(connectionConfig, poolOptions);
```

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `SNOWFLAKE_POOL_MAX` | 10 | Maximum pool connections |
| `SNOWFLAKE_POOL_MIN` | 2 | Minimum pool connections |
| `SNOWFLAKE_QUERY_TIMEOUT_MS` | 30000 | Query timeout in milliseconds |

## Viewing Data in Last9

1. Sign in to [Last9 Dashboard](https://app.last9.io)
2. Navigate to **APM > Services** to see your Snowflake service
3. View traces under **APM > Traces** and filter by `db.system = snowflake`
4. Create custom dashboards for Snowflake metrics under **Dashboards**

### Example Dashboard Queries

```promql
# Query throughput
rate(snowflake_queries_total[5m])

# P95 query duration
histogram_quantile(0.95, rate(snowflake_query_duration_bucket[5m]))

# Error rate
rate(snowflake_queries_errors_total[5m]) / rate(snowflake_queries_total[5m])

# Active connections
snowflake_connections_active
```

## Troubleshooting

### Telemetry Not Appearing

1. Verify environment variables are set:
   ```bash
   echo $OTEL_EXPORTER_OTLP_ENDPOINT
   echo $OTEL_EXPORTER_OTLP_HEADERS
   ```

2. Enable debug logging in `instrumentation.js`:
   ```javascript
   const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
   diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
   ```

3. Check network connectivity to Last9 endpoint:
   ```bash
   curl -v https://otlp.last9.io/v1/traces
   ```

### Snowflake Connection Issues

1. Verify Snowflake credentials:
   ```bash
   echo $SNOWFLAKE_ACCOUNT
   echo $SNOWFLAKE_USER
   ```

2. Test network connectivity:
   ```bash
   nc -zv <account>.snowflakecomputing.com 443
   ```

### High Cardinality Warnings

If you see cardinality warnings, ensure you're using bounded values for metric attributes. Avoid using raw SQL statements as attribute values; use parameterized query names instead.

## Best Practices

1. **Query Naming**: Use descriptive, bounded query names (e.g., `get-user-orders`, `update-inventory`) instead of dynamic values
2. **Sensitive Data**: Never include sensitive data in span attributes or logs; parameterize queries
3. **Sampling**: For high-throughput applications, configure trace sampling to reduce costs
4. **Connection Pooling**: Always use connection pooling in production environments
5. **Graceful Shutdown**: Ensure your application handles SIGTERM/SIGINT to flush pending telemetry

## Additional Resources

- [OpenTelemetry Database Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/database/database-spans/)
- [OpenTelemetry Node.js Documentation](https://opentelemetry.io/docs/languages/js/)
- [Snowflake Node.js Driver Documentation](https://docs.snowflake.com/en/developer-guide/node-js/nodejs-driver)
- [Last9 OpenTelemetry Integration Guide](https://docs.last9.io)
