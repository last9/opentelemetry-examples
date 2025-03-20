# Instrumenting Gin application with sqlx using OpenTelemetry

This example demonstrates how to instrument a simple Gin application with sqlx using OpenTelemetry and Last9.

## Prerequisites

- Recent version of Go
- [Last9](https://app.last9.io) account
- PostgreSQL

It uses the following libraries:

- [Gin](https://github.com/gin-gonic/gin)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go)
- [PostgreSQL](https://github.com/lib/pq)
- [sqlx](github.com/jmoiron/sqlx)

## Traces

It generates traces for HTTP requests, database queries, Redis commands, and external API calls.

### HTTP requests

- HTTP requests using [otelgin](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/github.com/gin-gonic/gin/otelgin)
- For HTTP requests, wrap the Gin router with the `otelgin.Middleware` middleware. Refer to [main.go](./main.go) for how to do this.

### Database queries

- Database queries using [otelsqlx](https://github.com/uptrace/opentelemetry-go-extra/tree/main/otelsqlx)
- For database queries, use the `otelsqlx` package to wrap the `sql.DB` object. Refer to `initDB()` in [users/controller.go](./users/controller.go) for more details.
- Read otelsqlx README for more details on how to do connect to database in different [ways](https://github.com/uptrace/opentelemetry-go-extra/tree/main/otelsqlx#usage)

To instrument sqlx, you need to connect to a database using the API provided by this package:

| sqlx                  | otelsqlx                  |
| --------------------- | ------------------------- |
| `sqlx.Connect`        | `otelsqlx.Connect`        |
| `sqlx.ConnectContext` | `otelsqlx.ConnectContext` |
| `sqlx.MustConnect`    | `otelsqlx.MustConnect`    |
| `sqlx.Open`           | `otelsqlx.Open`           |
| `sqlx.MustOpen`       | `otelsqlx.MustOpen`       |
| `sqlx.NewDb`          | not supported             |

### External API calls

- External API calls using [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp)
- For external API calls, use the `otelhttp` package to wrap the `http.Client` object. Refer to `getRandomJoke()` in [main.go](./main.go) for more details.

### Instrumentation packages

Following packages are used to instrument the Gin application. You can install them using the following commands:

```sh
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
go get go.opentelemetry.io/otel/sdk
go get go.opentelemetry.io/otel/sdk/metric
go get go.opentelemetry.io/otel/trace
go get github.com/uptrace/opentelemetry-go-extra/tree/main/otelsqlx
go get github.com/uptrace/opentelemetry-go-extra/tree/main/otelsql
```

## Exporting Telemetry Data to Last9

It uses GRPC exporters to export the traces and metrics to Last9. You can also use any other OpenTelemetry compatible backend.

## Running the application

1. After cloning the example, install the required packages using the following
   command:

```bash
go mod tidy
```

2. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

3. Next, run the commands below to set the environment variables.

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your endpoint
```

4. Run the Gin application:

```bash
go build -o gin && ./gin
```

5. Once the server is running, you can access the application at
   `http://localhost:8080` by default. The API endpoints are:

- GET `/users` - Get all users
- GET `/users/:id` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/:id` - Update a user
- DELETE `/users/:id` - Delete a user
- GET    `/joke` - Get a random joke using external API

6. Sign in to [Last9](https://app.last9.io) and visit the APM dashboard to see the traces and metrics.
