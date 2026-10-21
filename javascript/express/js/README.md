# Auto instrumenting Express application with OpenTelemetry

This example demonstrates how to auto-instrument an Express application with
OpenTelemetry. Make sure you have **Node.js v24.22.1** (or v22.23.4) or higher.

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
- @opentelemetry/instrumentation-runtime-node: 0.16.0
- @opentelemetry/sdk-metrics: 2.0.1
- @opentelemetry/exporter-metrics-otlp-http: 0.201.1
- @opentelemetry/exporter-metrics-otlp-grpc: 0.201.1 (optional)

**Resource detector packages (optional):**
- @opentelemetry/resource-detector-container: 0.7.2
- @opentelemetry/resource-detector-aws: 2.2.0
- @opentelemetry/resource-detector-gcp: 0.36.0
- @opentelemetry/resource-detector-azure: 0.9.0

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
  @opentelemetry/semantic-conventions@1.34.0 \
  @opentelemetry/instrumentation-runtime-node@0.16.0 \
  @opentelemetry/sdk-metrics@2.0.1 \
  @opentelemetry/exporter-metrics-otlp-http@0.201.1
# Optional, for OTLP metrics over gRPC:
# npm install @opentelemetry/exporter-metrics-otlp-grpc@0.201.1
```

1. To clone this example run the following command:

```bash
npx degit last9/opentelemetry-examples/javascript/express/js express
```

2. In the `express/env` directory create `.env` file and add the contents of
   `.env.example` file.

   ```bash
   cd env
   cp .env.example .env
   ```

3. Obtain the OTLP endpoint and the Auth Header from the Last9 dashboard and
   modify the values of the `OTLP_ENDPOINT` and `OTLP_AUTH_HEADER` variables
   accordingly in the `.env` file.

4. Next, install the dependencies by running the following command in the
   `express` directory:

```bash
npm install
```

5. To build the project, run the following command in the `express` directory:

```bash
npm run build
```

6. Start the server by running the following command:

```bash
npm run start
```

Once the server is running, you can access the application at
`http://localhost:3001` by default. Where you can make CRUD operations. The API
endpoints are:

- GET `/` - Welcome message
- GET `/api/users` - Get all users
- GET `/api/users/:id` - Get user by ID
- POST `/api/users/create` - Create a user
- PUT `/api/users/update/:id` - Update a user
- DELETE `/api/users/delete/:id` - Delete a user (added to match service)

7. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces in action.

![Traces](./traces.png)

## Database and HTTP client spans

`src/db-examples.js` is a second server that wraps PostgreSQL, MySQL, MongoDB,
Redis and axios calls in manual spans on top of auto-instrumentation: error
recording, span attributes, cache-aside, rate limiting, parallel HTTP calls and
a multi-step order workflow. Each route returns its `traceId`.

```bash
# Connection settings default to localhost; override as needed
export PG_HOST=localhost PG_DATABASE=testdb PG_USER=postgres PG_PASSWORD=password
export MYSQL_HOST=localhost MYSQL_DATABASE=testdb
export MONGO_URI=mongodb://localhost:27017 MONGO_DB=testdb
export REDIS_HOST=localhost REDIS_PORT=6379
npm run start:db-examples
```

The server starts even when a database is unreachable; its routes return 500
and record the error on the span. The endpoints are listed on startup.
`npm test` checks that contract against unreachable databases.

## Tail-based sampling with the Collector

Head-based sampling is set on the SDK with environment variables, for example
`OTEL_TRACES_SAMPLER=parentbased_traceidratio` and `OTEL_TRACES_SAMPLER_ARG=0.1`.
It decides at span creation, so it cannot keep errors or slow traces
selectively.

`otel-collector-config.yaml` decides after a trace completes and keeps 100% of
traces with errors, 100% of traces slower than 2s, and 10% of the rest:

```bash
export LAST9_OTLP_ENDPOINT=https://<your-last9-endpoint>
export LAST9_AUTH_HEADER="Basic <your-token>"
docker run --rm -p 4317:4317 -p 4318:4318 \
  -e LAST9_OTLP_ENDPOINT -e LAST9_AUTH_HEADER \
  -v "$PWD/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml" \
  otel/opentelemetry-collector-contrib:0.144.0

# Point the app at the Collector
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_TRACES_SAMPLER=always_on
npm start
```

## Optional: Using OpenTelemetry Resource Detectors

OpenTelemetry resource detectors can automatically detect environment metadata (such as AWS, GCP, Azure, or container info) and enrich your telemetry data. These are **optional** and can be enabled as needed.

### Example usage in `src/instrumentation.js`:

```js
// const { ContainerResourceDetector } = require('@opentelemetry/resource-detector-container');
// const { AwsEc2ResourceDetector, AwsEcsResourceDetector, AwsLambdaResourceDetector } = require('@opentelemetry/resource-detector-aws');
// const { GcpResourceDetector } = require('@opentelemetry/resource-detector-gcp');
// const { AzureVmResourceDetector } = require('@opentelemetry/resource-detector-azure');

// const sdk = new NodeSDK({
//   resourceDetectors: [
//     new ContainerResourceDetector(),
//     new AwsEc2ResourceDetector(),
//     new AwsEcsResourceDetector(),
//     new AwsLambdaResourceDetector(),
//     new GcpResourceDetector(),
//     new AzureVmResourceDetector(),
//   ],
//   ...
// });
```

See the [OpenTelemetry JS Contrib Resource Detectors documentation](https://github.com/open-telemetry/opentelemetry-js-contrib/tree/main/detectors/node) for more details.
