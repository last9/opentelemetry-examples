# Instrumenting Gin application (go v1.22) using OpenTelemetry

This example demonstrates how to integrate OpenTelemetry tracing with a Gin web application using Go 1.22. The implementation provides distributed tracing for HTTP requests and external API calls.

## Prerequisites

- Go 1.22 or higher
- [Last9](https://app.last9.io) account

It uses the following libraries:

- [Gin](https://github.com/gin-gonic/gin)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go)

## Traces

It generates traces for HTTP requests, and external API calls.

### HTTP requests

- HTTP requests using [otelgin](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/github.com/gin-gonic/gin/otelgin)
- For HTTP requests, wrap the Gin router with the `otelgin.Middleware` middleware. Refer to [main.go](./main.go) for how to do this.

### External API calls

- External API calls using [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp)
- For external API calls, use the `otelhttp` package to wrap the `http.Client` object. Refer to `getRandomJoke()` in [main.go](./main.go) for more details.

### Instrumentation packages

Following packages are used to instrument the Gin application. You can install them using the following commands:

```go
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin@v0.55.0
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp@v0.55.0
go get go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace@v0.55.0
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp@v1.30.0
go get go.opentelemetry.io/otel@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@v1.30.0
go get go.opentelemetry.io/otel/sdk@v1.30.0
go get go.opentelemetry.io/otel/exporters/stdout/stdoutmetric@v1.30.0
go get go.opentelemetry.io/otel/exporters/stdout/stdouttrace@v1.30.0
go get go.nhat.io/otelsql@v0.14.0
```

## Installation

1. Clone or download the project files
2. Install dependencies:

```bash
go mod tidy
```

3. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

4. Next, run the commands below to set the environment variables.

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your endpoint
```

### Optional Environment Variables

```bash
# Service resource attributes
export OTEL_RESOURCE_ATTRIBUTES="service.name=my-gin-api,service.version=1.0.0,deployment.environment=production"

# Alternative: Set individual resource attributes
export OTEL_SERVICE_NAME="my-gin-api"
export OTEL_SERVICE_VERSION="1.0.0"
```

## Running the Application

1. Set the required environment variables (see Configuration section)

2. Build and run the application:

```bash
go build -o gin1.22 && ./gin1.22
```

Or run directly:

```bash
go run main.go
```

3. Once the server is running, you can access the application at
   `http://localhost:8080` by default. The API endpoints are:

- GET `/users` - Get all users
- GET `/users/:id` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/:id` - Update a user
- DELETE `/users/:id` - Delete a user
- GET    `/joke` - Get a random joke using external API

4. Sign in to [Last9](https://app.last9.io) and visit the APM dashboard to see the traces.

## How to Add OpenTelemetry Instrumentation to an Existing Gin App

To instrument your existing Gin application with OpenTelemetry, follow these steps:

### 1. Install Required Packages

Add the following dependencies to your project:

```bash
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin@v0.55.0
go get go.opentelemetry.io/otel@v1.30.0
go get go.opentelemetry.io/otel/sdk@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc@v1.30.0
```

### 2. Initialize OpenTelemetry in Your App

- **Copy the `instrumentation.go` file from this repository into your project.** This file sets up the tracer and meter providers for you.
- Example setup (see this repo’s `instrumentation.go` for a full example):

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    // ... other imports
)

func initTracerProvider() *trace.TracerProvider {
    exporter, _ := otlptracehttp.New(context.Background())
    tp := trace.NewTracerProvider(trace.WithBatcher(exporter))
    otel.SetTracerProvider(tp)
    return tp
}
```

- Call this initialization early in your `main()`.

### 3. Add the OpenTelemetry Middleware to Gin

In your `main.go`, after creating your Gin router, add:

```go
import "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"

r := gin.Default()
r.Use(otelgin.Middleware("your-service-name"))
```

### 4. Instrument Handlers and External Calls

- To create spans in handlers, use the tracer:

```go
ctx, span := tracer.Start(c.Request.Context(), "operation-name")
defer span.End()
```

- For outgoing HTTP requests, wrap your client with `otelhttp`:

```go
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

client := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport)}
```

### 5. Set Environment Variables

Set the following before running your app:

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
```

### 6. Run Your Application

Build and run as usual. Traces and metrics will be sent to your configured OTLP endpoint.

---

**Tip:** For a complete example, see the files `main.go` and `instrumentation.go` in this repository.

---