# Instrumenting Golang Beego Application Using OpenTelemetry

This example demonstrates how to instrument a production-ready Beego v2 application with OpenTelemetry. All HTTP, database, Redis, and outgoing HTTP calls are fully traced and exported to your chosen backend (e.g., Last9, Jaeger, etc.).

## Prerequisites

- Recent version of Go
- [Last9](https://app.last9.io) account (or any OpenTelemetry-compatible backend)

It uses the following libraries:

- [Beego v2](https://github.com/beego/beego)
- [OpenTelemetry Go](https://github.com/open-telemetry/opentelemetry-go)
- [PostgreSQL](https://github.com/lib/pq)
- [Redis](https://github.com/redis/go-redis/v9)
- [otelsql](https://github.com/nhatthm/otelsql) for DB tracing
- [redisotel](https://github.com/redis/go-redis/tree/main/extra/redisotel) for Redis tracing

## Traces

The app generates traces for:
- HTTP requests (using a robust handler wrapper for correct status code propagation)
- Database queries (via otelsql)
- Redis commands (via redisotel)
- Outgoing HTTP requests (via Beego's httplib, can be extended with otelhttp)

### HTTP Requests

All Beego handlers are wrapped with a custom OpenTelemetry handler wrapper (`last9.WrapBeegoHandler`). This ensures:
- Correct parent/child span relationships
- Accurate HTTP status code propagation (even for errors)
- Robust, production-grade tracing

See [main.go](./main.go) and [last9/otelMiddleware.go](./last9/otelMiddleware.go) for details.

### Database Queries

Database queries are traced using [otelsql](https://github.com/nhatthm/otelsql). See `initDB()` in [users/controller.go](./users/controller.go).

### Redis Commands

Redis commands are traced using [redisotel](https://github.com/redis/go-redis/tree/main/extra/redisotel). See `initRedis()` in [main.go](./main.go).

### Outgoing HTTP Calls

Outgoing HTTP requests (e.g., `/joke` endpoint) are made using Beego's `httplib`. For full context propagation, you can use [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp) if you switch to the standard `http.Client`.

## Outgoing HTTP Call Instrumentation

This project demonstrates two approaches for instrumenting outgoing HTTP calls in Beego with OpenTelemetry:

- **/joke**: Uses Beego's `httplib` with a manually created span and context propagation for tracing the external call.
- **/joke2**: Uses Go's standard `net/http` client with `otelhttp.NewTransport` for automatic HTTP client span creation. The handler is wrapped with the Otel handler wrapper to ensure correct context propagation.

### Example Endpoints

- **GET /joke**
  - Returns a random joke (external API call traced via manual span)
  - Example:
    ```sh
    curl http://localhost:8080/joke
    # { "joke": "Joke: ...\n\n..." }
    ```
- **GET /joke2**
  - Returns a random joke (external API call traced via otelhttp)
  - Example:
    ```sh
    curl http://localhost:8080/joke2
    # { "joke": "Joke: ...\n\n..." }
    ```

### Tracing Details

- Both endpoints produce a parent HTTP server span and a child span for the outgoing HTTP request.
- **Correct context propagation is essential**: Always ensure outgoing HTTP calls are made within the Otel handler wrapper so the context includes the parent span.
- This pattern ensures robust, production-grade distributed tracing for all HTTP, DB, and Redis operations in your Beego app.

## Exporting Telemetry Data

The app uses the OTLP HTTP exporter by default. You can export traces to Last9, Jaeger, or any OpenTelemetry-compatible backend. Set the following environment variables:

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your OTLP endpoint
```

To enable local debugging, set:
```bash
export OTEL_CONSOLE_EXPORTER=true
```

## Running the Application

1. Install dependencies:

```bash
go mod tidy
```

2. Set the required environment variables (see above).

3. Build and run the app:

```bash
go build -o beegoapp && ./beegoapp
```

4. Access the API at `http://localhost:8080`:

- GET `/users` - Get all users
- GET `/users/:id` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/:id` - Update a user
- DELETE `/users/:id` - Delete a user
- GET `/joke` - Get a random joke using external API
- GET `/joke2` - Get a random joke using standard net/http with otelhttp

5. View traces in your configured backend (e.g., Last9 dashboard).

## Migrating an Existing Beego v2 App to OpenTelemetry with Last9

To instrument your existing Beego v2 application with OpenTelemetry and export traces to Last9, follow these steps:

### 1. Add Dependencies
Add the following to your `go.mod`:

```bash
go get github.com/beego/beego/v2
# OpenTelemetry core and exporters
go get go.opentelemetry.io/otel
# OTLP HTTP exporter
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
# Otel SDK
go get go.opentelemetry.io/otel/sdk
# Otel SQL instrumentation
go get go.nhat.io/otelsql
# Redis Otel instrumentation
go get github.com/redis/go-redis/extra/redisotel/v9
```

### 2. Initialize OpenTelemetry Early
In your `main.go`, initialize Otel as early as possible. Use the provided `last9/instrumentation.go` or similar:

```go
import "beego_example/last9"

func main() {
    i := last9.NewInstrumentation("your-service-name")
    defer func() {
        _ = i.TracerProvider.Shutdown(context.Background())
    }()
    // ... rest of your setup ...
}
```

Set the following environment variables for Last9:
```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # Your Last9 Otel endpoint
```

### 3. Wrap All Handlers for Tracing
For robust HTTP tracing and correct status code propagation, wrap all your Beego handlers using the handler wrapper:

```go
import "beego_example/last9"

// Example for a GET handler
web.Router("/users", &UsersControllerWrapper{}, "get:GetUsers")

// In your controller:
func (c *UsersControllerWrapper) GetUsers() {
    last9.WrapBeegoHandler("your-service-name", getUsersHandler)(&c.Controller)
}

func getUsersHandler(ctx *web.Controller) {
    // ... your logic ...
    ctx.Ctx.Output.SetStatus(200) // Always set status code
    ctx.Data["json"] = ...
    ctx.ServeJSON()
}
```

### 4. Instrument Database and Redis
- Use `otelsql` to wrap your DB driver (see `initDB()` in `users/controller.go`).
- Use `redisotel` to instrument your Redis client (see `initRedis()` in `main.go`).

### 5. Propagate Context
Pass `ctx.Ctx.Request.Context()` from your Beego controller to all DB and Redis calls to ensure trace context propagation.

### 6. Always Set HTTP Status Codes
Explicitly set the status code in every handler, even for successful responses, to ensure correct trace data.

### 7. Verify Traces
Run your app, make requests, and verify traces appear in Last9 with correct parent/child relationships and status codes.

**Tip:** For local debugging, set `OTEL_CONSOLE_EXPORTER=true` to print traces to the console.
