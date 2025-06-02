# Instrumenting Golang Beego application using OpenTelemetry

This example demonstrates how to instrument a simple Beego application with
OpenTelemetry. **Note: All OpenTelemetry instrumentation is currently commented out.**

## Prerequisites

- Recent version of Go
- [Last9](https://app.last9.io) account

It uses the following libraries:

- [Beego](https://github.com/astaxie/beego)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go) (commented out)
- [PostgreSQL](https://github.com/lib/pq)
- [Redis](https://github.com/redis/go-redis/v9)

## Traces

It generates traces for HTTP requests, database queries, Redis commands, and external API calls. **(Currently commented out)**

### HTTP requests

- HTTP requests would use a middleware for tracing (currently commented out).
- For HTTP requests, wrap the Beego router with the middleware. Refer to [main.go](./main.go) for how to do this (commented out).

### Database queries

- Database queries using [otelsql](https://github.com/nhatthm/otelsql) (commented out).
- For database queries, use the `otelsql` package to wrap the `sql.DB` object. Refer to `initDB()` in [users/controller.go](./users/controller.go) for more details.

### Redis commands

- Redis commands using [redisotel](https://github.com/redis/redis-go-cluster/tree/main/redisotel) (commented out).
- For Redis commands, use the `redisotel` package to wrap the `redis.Client` object. Refer to `initRedis()` in [main.go](./main.go) for more details.

### External API calls

- External API calls using [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp) (commented out).
- For external API calls, use the `otelhttp` package to wrap the `http.Client` object. Refer to `getRandomJokeBeego()` in [main.go](./main.go) for more details.

### Instrumentation packages

Following packages are used to instrument the Beego application (currently commented out). You can install them using the following commands:

```sh
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
go get go.opentelemetry.io/otel/sdk
go get go.opentelemetry.io/otel/trace
go get github.com/redis/go-redis/extra/redisotel/v9
go get go.nhat.io/otelsql
```

Refer to [last9/instrumentation.go](./last9/instrumentation.go) for more details on initializing the instrumentation (currently commented out).

Add following code to your main function to initialize the instrumentation as early as possible in your application lifecycle (currently commented out):

```go
// i := last9.NewInstrumentation()
// defer func() {
//   if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
//     log.Printf("Error shutting down tracer provider: %v", err)
//   }
// }()
```

## Exporting Telemetry Data to Last9

It uses GRPC exporters to export the traces and metrics to Last9. You can also use any other OpenTelemetry compatible backend. **(Currently commented out)**

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
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your Last9 endpoint
```

4. Run the Beego application:

```bash
go build -o beegoapp && ./beegoapp
```

5. Once the server is running, you can access the application at
   `http://localhost:8080` by default. The API endpoints are:

- GET `/users` - Get all users
- GET `/users/:id` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/:id` - Update a user
- DELETE `/users/:id` - Delete a user
- GET `/joke` - Get a random joke using external API

6. Sign in to [Last9](https://app.last9.io) and visit the APM dashboard to see the traces and metrics (when instrumentation is enabled).
