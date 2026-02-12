# Instrumenting Snowflake with OpenTelemetry

This example demonstrates how to instrument Snowflake queries with OpenTelemetry
in a Node.js application. It provides visibility into query performance,
connection health, and usage patterns.

**Tested with:** Node.js v18, Node.js v20, Node.js v22

## OpenTelemetry Packages Used

- @opentelemetry/api: 1.9.0
- @opentelemetry/auto-instrumentations-node: 0.59.0
- @opentelemetry/exporter-trace-otlp-http: 0.201.1
- @opentelemetry/exporter-metrics-otlp-http: 0.201.1
- @opentelemetry/instrumentation: 0.201.1
- @opentelemetry/resources: 2.0.1
- @opentelemetry/sdk-node: 0.201.1
- @opentelemetry/sdk-trace-base: 2.0.1
- @opentelemetry/sdk-trace-node: 2.0.1
- @opentelemetry/sdk-metrics: 2.0.1
- @opentelemetry/semantic-conventions: 1.34.0
- snowflake-sdk: 1.9.0

## Prerequisites

1. **Snowflake Account**: Active Snowflake account with credentials
2. **Required Information**:
   - Account identifier (e.g., `ts73027.ap-south-1.aws`)
   - Username and password
   - Warehouse, database, and schema names
3. **Last9 Account**: Sign up at [Last9](https://app.last9.io) to get OTLP credentials

## Quick Start

1. Clone this example:

```bash
npx degit last9/opentelemetry-examples/javascript/snowflake snowflake
cd snowflake
```

2. Create environment configuration:

```bash
cp env/.env.example env/.env
```

3. Edit `env/.env` with your Snowflake and Last9 credentials:

```bash
# Snowflake Configuration
SNOWFLAKE_ACCOUNT=your_account.region.aws
SNOWFLAKE_USER=your_username
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_DATABASE=your_database
SNOWFLAKE_SCHEMA=your_schema

# OpenTelemetry Configuration
OTEL_SERVICE_NAME=snowflake-app
OTEL_EXPORTER_OTLP_ENDPOINT=https://<your_last9_endpoint>
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your_auth_token>
```

4. Install dependencies:

```bash
npm install
```

5. Start the server:

```bash
npm start
```

## API Endpoints

Once running, the following endpoints are available:

- `GET /` - Welcome message and endpoint list
- `GET /health` - Health check
- `GET /api/query` - Execute a sample Snowflake query
- `POST /api/query` - Execute a custom query (body: `{ "sql": "SELECT ...", "queryName": "my-query" }`)

## Testing the Integration

```bash
# Health check
curl http://localhost:3000/health

# Sample query
curl http://localhost:3000/api/query

# Custom query
curl -X POST http://localhost:3000/api/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT CURRENT_TIMESTAMP()", "queryName": "timestamp-query"}'
```

## Telemetry Collected

### Traces

Each Snowflake query creates a span with attributes:
- `db.system`: "snowflake"
- `db.name`: Database name
- `db.statement`: SQL query text
- `query.name`: Custom query identifier
- `db.rows_returned`: Number of rows returned
- `db.query_duration_ms`: Query execution time

### Metrics

Custom metrics collected:

| Metric | Type | Description |
|--------|------|-------------|
| `snowflake.queries.total` | Counter | Total queries executed |
| `snowflake.query.duration` | Histogram | Query duration in ms |
| `snowflake.queries.errors` | Counter | Failed queries |
| `snowflake.connections.active` | UpDownCounter | Active connections |
| `snowflake.rows.returned` | Histogram | Rows returned per query |

## Project Structure

```
snowflake/
├── env/
│   └── .env.example       # Environment template
├── src/
│   ├── instrumentation.js # OpenTelemetry setup
│   ├── snowflake-client.js # Snowflake pool and metrics
│   └── server.js          # Express application
├── package.json
├── .gitignore
└── README.md
```

## Configuration Options

### Connection Pool Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SNOWFLAKE_POOL_MAX` | 5 | Maximum pool connections |
| `SNOWFLAKE_POOL_MIN` | 1 | Minimum pool connections |
| `SNOWFLAKE_POOL_TIMEOUT_MS` | 30000 | Pool usage timeout |
| `SNOWFLAKE_POOL_RETRY_LIMIT` | 3 | Connection retry attempts |
| `SNOWFLAKE_POOL_RETRY_DELAY_MS` | 2000 | Delay between retries |
| `SNOWFLAKE_QUERY_TIMEOUT_MS` | 20000 | Query execution timeout |

## Viewing Traces

Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
dashboard to see traces and metrics.

## Troubleshooting

### Connection Issues

```bash
# Verify environment variables
echo $SNOWFLAKE_ACCOUNT
echo $SNOWFLAKE_USER

# Test connectivity
nc -zv <account>.snowflakecomputing.com 443
```

### Query Timeout Errors

- Increase `SNOWFLAKE_QUERY_TIMEOUT_MS`
- Check query complexity in Snowflake query profiler

### Telemetry Not Appearing

```bash
# Verify OTLP configuration
echo $OTEL_EXPORTER_OTLP_ENDPOINT
echo $OTEL_EXPORTER_OTLP_HEADERS

# Enable debug logging in instrumentation.js:
# const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
# diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
```
