# net/http Instrumentation Example

This example demonstrates how to instrument a Go application using the standard `net/http` package with the Last9 Go Agent for automatic OpenTelemetry tracing and metrics.

## Features

- **Automatic server-side tracing** - All incoming HTTP requests are traced
- **Automatic HTTP client tracing** - Outgoing HTTP requests are traced with context propagation
- **Multiple instrumentation patterns** - Choose the best approach for your application
- **Minimal code changes** - Just wrap your handlers or mux

## Prerequisites

- Go 1.22 or later
- Last9 account with OTLP endpoint

## Quick Start

1. Set environment variables:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="<your-last9-otlp-endpoint>"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"
export OTEL_SERVICE_NAME="nethttp-example"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
```

2. Run the example:

```bash
go mod tidy
go run main.go
```

3. Make some requests:

```bash
# Get all users
curl http://localhost:8080/users

# Get a specific user
curl http://localhost:8080/users/1

# Create a user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Charlie","email":"charlie@example.com"}'

# Get a joke (demonstrates downstream HTTP call tracing)
curl http://localhost:8080/joke

# Health check
curl http://localhost:8080/health
```

## Instrumentation Patterns

### Pattern 1: Instrumented ServeMux (Recommended)

Best for new applications. Each handler is automatically traced with the route pattern as the span name.

```go
import "github.com/last9/go-agent/instrumentation/nethttp"

mux := nethttp.NewServeMux()
mux.HandleFunc("/users", usersHandler)
mux.HandleFunc("/users/{id}", userHandler)
http.ListenAndServe(":8080", mux)
```

### Pattern 2: Wrap Existing Handler

Best for existing applications. Wrap your existing `http.ServeMux` or any `http.Handler`.

```go
mux := http.NewServeMux()
mux.HandleFunc("/api/data", dataHandler)
http.ListenAndServe(":8080", nethttp.WrapHandler(mux))
```

### Pattern 3: Wrap Individual Handlers

Best for fine-grained control. Wrap specific handlers with custom operation names.

```go
handler := nethttp.Handler(myHandler, "/users/{id}")
http.Handle("/users/", handler)
```

### Pattern 4: Drop-in ListenAndServe

Simplest approach for existing code. Just replace `http.ListenAndServe` with `nethttp.ListenAndServe`.

```go
mux := http.NewServeMux()
mux.HandleFunc("/api", apiHandler)
nethttp.ListenAndServe(":8080", mux)  // Auto-wraps the handler
```

### Pattern 5: Middleware

For use with middleware chains.

```go
handler := nethttp.Middleware("my-api")(baseHandler)
```

## HTTP Client Instrumentation

For outgoing HTTP requests, use the instrumented HTTP client:

```go
import httpagent "github.com/last9/go-agent/integrations/http"

client := httpagent.NewClient(&http.Client{
    Timeout: 10 * time.Second,
})

// Create request with context for trace propagation
req, _ := http.NewRequestWithContext(ctx, "GET", "https://api.example.com", nil)
resp, err := client.Do(req)
```

## Context Propagation

For manual context propagation (advanced use case):

```go
// Extract trace context from incoming request
ctx := nethttp.ExtractContext(r.Context(), r)

// Inject trace context into outgoing request
outReq, _ := http.NewRequestWithContext(ctx, "GET", "http://downstream/api", nil)
nethttp.InjectContext(ctx, outReq)
```

## What Gets Traced

### Server-side (automatic)
- HTTP method and URL path
- Response status code
- Request/response sizes
- Duration

### Client-side (automatic with instrumented client)
- HTTP method and URL
- Response status code
- Duration
- Trace context propagation (traceparent header)

## Metrics (Automatic)

The following metrics are collected automatically:

- `http.server.request.duration` - Server request latency histogram
- `http.server.request.body.size` - Request body size histogram
- `http.server.response.body.size` - Response body size histogram
- `http.server.active_requests` - Current number of active requests

## Testing

View traces in your Last9 dashboard after making requests to the server.

## Comparison with Framework-Specific Instrumentation

| Approach | Code Changes | Best For |
|----------|--------------|----------|
| **net/http** (this example) | Minimal | Pure stdlib applications |
| **Gin** | Minimal | Gin framework users |
| **Chi** | Minimal | Chi router users |
| **Echo** | Minimal | Echo framework users |
| **Gorilla Mux** | Minimal | Gorilla Mux users |

All approaches provide equivalent observability - choose based on your existing framework.
