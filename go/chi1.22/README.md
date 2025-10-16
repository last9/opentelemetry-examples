# Instrumenting Chi application (go v1.22) using OpenTelemetry

This example demonstrates how to integrate OpenTelemetry tracing with a Chi web application using Go 1.22. The implementation provides distributed tracing for HTTP requests and external API calls.

## Prerequisites

- Go 1.22 or higher
- [Last9](https://app.last9.io) account

It uses the following libraries:

- [Chi](https://github.com/go-chi/chi)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go)

## Traces

It generates traces for HTTP requests, and external API calls.

### HTTP requests

- HTTP requests using [otelchi](https://github.com/riandyrn/otelchi)
- For HTTP requests, wrap the Chi router with the `otelchi.Middleware` middleware. Refer to [main.go](./main.go) for how to do this.

### External API calls

- External API calls using [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp)
- For external API calls, use the `otelhttp` package to wrap the `http.Client` object. Refer to `getRandomJoke()` in [main.go](./main.go) for more details.

### Instrumentation packages

Following packages are used to instrument the Chi application. You can install them using the following commands:

```go
go get github.com/go-chi/chi/v5@v5.1.0
go get github.com/riandyrn/otelchi@v0.8.0
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
export OTEL_RESOURCE_ATTRIBUTES="service.name=my-chi-api,service.version=1.0.0,deployment.environment=production"

# Alternative: Set individual resource attributes
export OTEL_SERVICE_NAME="my-chi-api"
export OTEL_SERVICE_VERSION="1.0.0"
```

## Running the Application

1. Set the required environment variables (see Configuration section)

2. Build and run the application:

```bash
go build -o chi1.22 && ./chi1.22
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

## Testing the Application

### Testing External API Calls

The `/joke` endpoint makes an external API call to fetch a random joke, demonstrating HTTP client instrumentation with OpenTelemetry:

```bash
# Get a random joke (triggers external API call)
curl http://localhost:8080/joke
```

Expected response:
```json
{
  "setup": "What do you call a bear with no teeth?",
  "punchline": "A gummy bear!"
}
```

This endpoint demonstrates:
- External HTTP call instrumentation using `otelhttp.NewTransport()`
- HTTP trace propagation using `otelhttptrace.NewClientTrace()`
- Custom span attributes for the joke data
- Error handling with span status and error recording

### Testing Database and Redis Operations

The user endpoints demonstrate database (PostgreSQL) and caching (Redis) instrumentation:

#### 1. Create a User (Database Write + Redis Cache Update)

```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "id": "1",
    "name": "John Doe",
    "email": "john@example.com"
  }'
```

This triggers:
- PostgreSQL INSERT operation (traced via `otelsql`)
- Redis SET operation (traced via `redisotel`)
- Redis DEL operation to invalidate users list cache

#### 2. Get All Users (Database Read + Redis Cache)

```bash
# First call - fetches from database and caches in Redis
curl http://localhost:8080/users

# Second call - fetches from Redis cache (faster)
curl http://localhost:8080/users
```

This demonstrates:
- Cache hit/miss behavior
- PostgreSQL SELECT operation (on cache miss)
- Redis GET operation (on every call)
- Redis SET operation (on cache miss)

#### 3. Get User by ID (Database Read + Redis Cache)

```bash
curl http://localhost:8080/users/1
```

This triggers:
- Redis GET for individual user key
- PostgreSQL SELECT by ID (on cache miss)
- Redis SET for individual user (on cache miss)

#### 4. Update User (Database Update + Redis Cache Update)

```bash
curl -X PUT http://localhost:8080/users/1 \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "name=Jane Doe"
```

This triggers:
- Redis GET to fetch current user
- Database UPDATE operation (when implemented)
- Redis cache update

#### 5. Delete User (Database Delete + Redis Cache Invalidation)

```bash
curl -X DELETE http://localhost:8080/users/1
```

This triggers:
- Database DELETE operation
- Redis cache invalidation

### Observing Traces in Last9

After making the above requests, you can observe the following in the Last9 APM dashboard:

1. **HTTP Request Traces**: Each incoming request will have a trace showing the full request lifecycle
2. **Database Spans**: PostgreSQL operations will appear as child spans with query details
3. **Redis Spans**: Redis operations will appear as child spans with command details
4. **External API Spans**: The joke endpoint will show HTTP client spans with request/response details
5. **Custom Attributes**: User IDs, joke content, and other metadata attached to spans

### Prerequisites for Database Operations

Before testing database operations, ensure:

1. **PostgreSQL is running** and accessible at `localhost:5432`
2. **Database `otel_demo` exists**:
   ```bash
   createdb otel_demo
   ```
3. **Users table is created**:
   ```sql
   CREATE TABLE users (
       id VARCHAR(50) PRIMARY KEY,
       name VARCHAR(255) NOT NULL,
       email VARCHAR(255) NOT NULL UNIQUE
   );
   ```

4. **Redis is running** at `localhost:6379`:
   ```bash
   redis-server
   ```

## How to Add OpenTelemetry Instrumentation to an Existing Chi App

To instrument your existing Chi application with OpenTelemetry, follow these steps:

### 1. Install Required Packages

Add the following dependencies to your project:

```bash
go get github.com/go-chi/chi/v5@v5.1.0
go get github.com/riandyrn/otelchi@v0.8.0
go get go.opentelemetry.io/otel@v1.30.0
go get go.opentelemetry.io/otel/sdk@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc@v1.30.0
```

### 2. Initialize OpenTelemetry in Your App

- **Copy the `instrumentation.go` file from this repository into your project.** This file sets up the tracer and meter providers for you.
- Example setup (see this repo's `instrumentation.go` for a full example):

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

### 3. Add the OpenTelemetry Middleware to Chi

In your `main.go`, after creating your Chi router, add:

```go
import (
    "github.com/go-chi/chi/v5"
    "github.com/riandyrn/otelchi"
)

r := chi.NewRouter()
r.Use(otelchi.Middleware("your-service-name", otelchi.WithChiRoutes(r)))
```

### 4. Instrument Handlers and External Calls

- To create spans in handlers, use the tracer:

```go
ctx, span := tracer.Start(r.Context(), "operation-name")
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

## Project Structure

```
chi1.22/
├── main.go                 # Main application entry point with Chi router
├── instrumentation.go      # OpenTelemetry setup and configuration
├── go.mod                  # Go module dependencies
├── README.md              # This file
└── users/
    ├── user.go            # User data model
    ├── controller.go      # Business logic for user operations
    └── handler.go         # HTTP handlers for Chi router
```

## Key Differences from Other Frameworks

### Chi vs Gin

1. **Handler Signatures**: Chi uses standard `http.HandlerFunc` (`func(w http.ResponseWriter, r *http.Request)`) while Gin uses `gin.HandlerFunc` with a custom context.

2. **Middleware**: Chi uses `otelchi.Middleware()` from the risingwave-otel package, while Gin uses `otelgin.Middleware()`.

3. **URL Parameters**: Chi uses `chi.URLParam(r, "id")` to extract URL parameters, while Gin uses `c.Param("id")`.

4. **JSON Responses**: Chi uses standard `json.NewEncoder(w).Encode()` while Gin provides helper methods like `c.JSON()`.

## Features

- Full OpenTelemetry instrumentation for HTTP requests
- Redis caching with OpenTelemetry tracing
- PostgreSQL database operations with tracing
- External API calls with distributed tracing
- Custom span attributes for better observability
- Error tracking and span status management

## Notes

- Make sure Redis is running on `localhost:6379` or update the connection string in `main.go`
- Make sure PostgreSQL is running with the database `otel_demo` or update the DSN in `users/controller.go`
- The database schema should include a `users` table with columns: `id`, `name`, `email`
