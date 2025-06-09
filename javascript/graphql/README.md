# Apollo GraphQL + OpenTelemetry Example

This example demonstrates how to instrument an Apollo GraphQL server (Node.js) with OpenTelemetry, ensuring that HTTP spans are named after the actual GraphQL operation (query/mutation name) rather than the generic endpoint.

## Features

- Apollo Server with Express
- OpenTelemetry tracing for HTTP, Express, and GraphQL
- Docker support for easy deployment
- Load generator script for stress testing the API

## Setup (Local)

```bash
npm install
npm start
```

The server will be available at http://localhost:4000/graphql

**OpenTelemetry package versions used in this example:**

- @opentelemetry/api: 1.9.0
- @opentelemetry/auto-instrumentations-node: 0.59.0
- @opentelemetry/exporter-trace-otlp-grpc: 0.201.1
- @opentelemetry/exporter-trace-otlp-http: 0.201.1
- @opentelemetry/instrumentation: 0.201.1
- @opentelemetry/resources: 2.0.1
- @opentelemetry/sdk-node: 0.201.1
- @opentelemetry/sdk-trace-base: 2.0.1
- @opentelemetry/sdk-trace-node: 2.0.1
- @opentelemetry/semantic-conventions: 1.34.0
- @opentelemetry/instrumentation-express: 0.45.0
- @opentelemetry/instrumentation-graphql: 0.45.0
- @opentelemetry/instrumentation-http: 0.45.0

**To install these exact OpenTelemetry dependencies:**

```bash
npm install \
  @opentelemetry/api@1.9.0 \
  @opentelemetry/auto-instrumentations-node@0.59.0 \
  @opentelemetry/exporter-trace-otlp-grpc@0.201.1 \
  @opentelemetry/exporter-trace-otlp-http@0.201.1 \
  @opentelemetry/instrumentation@0.201.1 \
  @opentelemetry/resources@2.0.1 \
  @opentelemetry/sdk-node@0.201.1 \
  @opentelemetry/sdk-trace-base@2.0.1 \
  @opentelemetry/sdk-trace-node@2.0.1 \
  @opentelemetry/semantic-conventions@1.34.0
```

## Running with Docker

```bash
docker build -t graphql-server .
docker run -p 4000:4000 graphql-server
```

## Load Generation

A load generator script is provided to simulate concurrent API usage:

```bash
node load-generator.js
```

You can customize the load:
```bash
GRAPHQL_URL=http://localhost:4000/graphql CONCURRENCY=10 REQUESTS_PER_WORKER=50 node load-generator.js
```
- `GRAPHQL_URL`: URL of the GraphQL endpoint (default: http://localhost:4000/graphql)
- `CONCURRENCY`: Number of parallel workers (default: 5)
- `REQUESTS_PER_WORKER`: Number of requests per worker (default: 20)

## Notes
- The OpenTelemetry setup customizes HTTP span names so that each span reflects the GraphQL operation name (e.g., `query books`, `mutation addBook`) instead of just `/graphql`.
- Traces are exported using the OTLP HTTP exporter. If you do not have an OpenTelemetry Collector running on `localhost:4318`, you may see connection errors in the logs. This does not affect API or load testing.
- You can configure the exporter endpoint in `instrumentation.js`. 