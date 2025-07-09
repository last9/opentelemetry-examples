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
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc@v1.30.0
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