# Instrumenting Gorilla Mux application using OpenTelemetry

This example demonstrates how to instrument a simple Gorilla Mux application with
OpenTelemetry.

## Prerequisites

- Recent version of Go
- [Last9](https://app.last9.io) account

It uses the following libraries:

- [Gorilla Mux](https://github.com/gorilla/mux)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go)
- [PostgreSQL](https://github.com/lib/pq)
- [Redis](https://github.com/redis/go-redis/v9)

## Traces

It generates traces for HTTP requests, database queries, Redis commands, and external API calls.

### HTTP requests

- HTTP requests using [otelmux](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/github.com/gorilla/mux/otelmux)
- For HTTP requests, wrap the Mux router with the `otelmux.Middleware` middleware. Refer to [main.go](./main.go) for how to do this.

### Database queries

- Database queries using [otelsql](https://github.com/nhatthm/otelsql)
- For database queries, use the `otelsql` package to wrap the `sql.DB` object. Refer to `initDB()` in [users/controller.go](./users/controller.go) for more details.

### Redis commands

- Redis commands using [redisotel](https://github.com/redis/redis-go-cluster/tree/main/redisotel).
- For Redis commands, use the `redisotel` package to wrap the `redis.Client` object. Refer to `initRedis()` in [users/controller.go](./users/controller.go) for more details.

### External API calls

- External API calls using [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp)
- For external API calls, use the `otelhttp` package to wrap the `http.Client` object. Refer to `getRandomJoke()` in [main.go](./main.go) for more details.

### Instrumentation packages

Following packages are used to instrument the Gorilla Mux application. You can install them using the following commands:

```sh
go get go.opentelemetry.io/contrib/instrumentation/github.com/gorilla/mux/otelmux
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
go get go.opentelemetry.io/otel/sdk
go get go.opentelemetry.io/otel/sdk/metric
go get go.opentelemetry.io/otel/trace
go get github.com/redis/go-redis/extra/redisotel/v9
go get go.nhat.io/otelsql
```

## Metrics

It also generates metrics for database queries using [otelsql](https://github.com/nhatthm/otelsql)

## Exporting Telemetry Data to Last9

It uses GRPC exporters to export the traces and metrics to Last9. You can also use any other OpenTelemetry compatible backend.

## Running the application

1. After cloning the example, install the required packages using the following
   command:

```bash
go mod tidy
```

2. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io/integrations?category=all&integration=OpenTelemetry).
   The Auth header is required in the next step.

3. Next, run the commands below to set the environment variables.

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your endpoint
```

4. Run the Gorilla Mux application:

```bash
go build -o server && ./server
```

5. Once the server is running, you can access the application at
   `http://localhost:8080` by default. The API endpoints are:

- GET `/users` - Get all users
- GET `/users/{id}` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/{id}` - Update a user
- DELETE `/users/{id}` - Delete a user
- GET `/joke` - Get a random joke using external API

6. Sign in to [Last9](https://app.last9.io) and visit the [Trace explorer](https://app.last9.io/traces) to see the traces.
