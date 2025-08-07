# Instrumenting Gin application using OpenTelemetry

**This example demonstrates:**
- **otelsql** instrumentation (raw SQL, see `/users` endpoints, code in `users/controller.go`)
- **GORM + OpenTelemetry** plugin (see `/posts` endpoints, code in `main.go`)
- **Enhanced Exception Handling** with detailed error recording and stack traces (see `common/exception.go`)

See below for details on all approaches.

## Prerequisites

- Recent version of Go
- [Last9](https://app.last9.io) account

It uses the following libraries:

- [Gin](https://github.com/gin-gonic/gin)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go)
- [PostgreSQL](https://github.com/lib/pq)
- [Redis](https://github.com/redis/go-redis/v9)
- [GORM](https://gorm.io/)
- [GORM OpenTelemetry Tracing Plugin](https://github.com/go-gorm/opentelemetry)

## Traces

It generates traces for HTTP requests, database queries, Redis commands, and external API calls.

### HTTP requests

- HTTP requests using [otelgin](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/github.com/gin-gonic/gin/otelgin)
- For HTTP requests, wrap the Gin router with the `otelgin.Middleware` middleware. Refer to [main.go](./main.go) for how to do this.

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

Following packages are used to instrument the Gin application. You can install them using the following commands:

#### Core OpenTelemetry packages

```bash
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
go get go.opentelemetry.io/otel/sdk
go get go.opentelemetry.io/otel/sdk/metric
go get go.opentelemetry.io/otel/trace
```

#### Otel package for Gin

```bash
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin
```

#### Otel package for Redis

```bash
go get github.com/redis/go-redis/extra/redisotel/v9
```

#### Otel package for raw SQL

```bash
go get go.nhat.io/otelsql
```

#### Otel package for Gorm

```bash
go get gorm.io/plugin/opentelemetry/tracing
```

## Metrics

It also generates metrics for database queries using [otelsql](https://github.com/nhatthm/otelsql)

## Exporting Telemetry Data to Last9

It uses GRPC exporters to export the traces and metrics to Last9. You can also use any other OpenTelemetry compatible backend.

## Endpoints

- GET `/users` - Get all users (**otelsql, raw SQL**)
- GET `/users/:id` - Get a user by ID (**otelsql, raw SQL**)
- POST `/users` - Create a new user (**otelsql, raw SQL**)
- PUT `/users/:id` - Update a user (**otelsql, raw SQL**)
- DELETE `/users/:id` - Delete a user (**otelsql, raw SQL**)
- GET `/joke` - Get a random joke using external API
- GET `/posts` - Get all posts (**GORM + OpenTelemetry**)
- POST `/posts` - Create a new post (**GORM + OpenTelemetry**)
- GET `/test-exception` - Test panic recovery and exception handling
- GET `/test-error` - Test error recording with stack traces

## Database Instrumentation Approaches

### 1. otelsql (raw SQL, `/users` endpoints)
- Uses the [otelsql](https://github.com/nhatthm/otelsql) package to instrument raw SQL queries.
- See `users/controller.go` for setup and usage.
- All `/users` endpoints use this approach.

**Example usage:**
```go
import (
    "database/sql"
    "go.nhat.io/otelsql"
)

db, err := sql.Open(otelsql.DriverName("postgres"), dsn)
// Use db as usual, context will be propagated if you use db.QueryContext, db.ExecContext, etc.
```

### 2. GORM + OpenTelemetry (`/posts` endpoints)
- Uses [GORM](https://gorm.io/) with the [OpenTelemetry tracing plugin](https://github.com/go-gorm/opentelemetry).
- See `main.go` for setup and usage.
- All `/posts` endpoints use this approach.

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
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>" # change this to your Last9 otel authorization header
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # change this to your Last9 Otel endpoint
export OTEL_SERVICE_NAME="<service_name>" # change this to correct service name
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local" # change this to correct deployment environment
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

## Exception Handling

This example includes enhanced exception handling that records detailed error information in OpenTelemetry traces and sends them to Last9. The exception handling functions are defined in `common/exception.go` as a shared package that can be imported by both the main application and user handlers.

### Key Features:
- **Detailed Exception Recording**: Captures exception details, stack traces, and custom attributes
- **Automatic Span Management**: Integrates with OpenTelemetry spans for proper trace context
- **Last9 Integration**: Sends all exception data to Last9 for monitoring and alerting
- **Development vs Production**: Different levels of detail based on environment

### Package Structure:

```
common/
└── exception.go    # Shared exception handling functions
main.go            # Uses common.RecordExceptionInSpan()
users/
└── handlers.go    # Uses common.RecordExceptionInSpan()
```

### Available Functions:

#### `common.RecordExceptionInSpan(c *gin.Context, message string, errInput ...interface{})`
Records a simple exception with custom attributes.

```go
import "gin_example/common"

common.RecordExceptionInSpan(c, "Database connection failed", 
    "error_type", "connection_error",
    "database", "postgres",
    "details", err.Error())
```

#### `common.RecordExceptionWithStack(c *gin.Context, err error, additionalInfo ...interface{})`
Records an exception with full stack trace and error details.

```go
import "gin_example/common"

common.RecordExceptionWithStack(c, err,
    "operation", "create_user",
    "table", "users",
    "user_email", user.Email)
```

### Usage Examples:

#### Database Errors
```go
if err := db.Create(&user).Error; err != nil {
    common.RecordExceptionWithStack(c, err,
        "operation", "create_user",
        "table", "users",
        "user_email", user.Email)
    c.JSON(500, gin.H{"error": "Database error"})
    return
}
```

#### Validation Errors
```go
if err := c.ShouldBindJSON(&user); err != nil {
    common.RecordExceptionInSpan(c, "Invalid JSON input", 
        "error_type", "validation_error",
        "field", "request_body",
        "details", err.Error())
    c.JSON(400, gin.H{"error": "Invalid input"})
    return
}
```

#### Panic Recovery
```go
defer func() {
    if r := recover(); r != nil {
        common.RecordExceptionInSpan(c, "Panic occurred", 
            "panic_value", fmt.Sprintf("%v", r),
            "endpoint", "/risky-operation")
        c.JSON(500, gin.H{"error": "Internal server error"})
    }
}()
```

### How It Works:

1. **Shared Package**: The `common` package contains all exception handling functions
2. **Import in Multiple Files**: Both `main.go` and `users/handlers.go` import `gin_example/common`
3. **Consistent Usage**: All exception calls use `common.RecordExceptionInSpan()` or `common.RecordExceptionWithStack()`
4. **Automatic Last9 Integration**: All exceptions are automatically sent to Last9 with detailed context

### Environment Configuration:

```bash
# For enhanced debugging in development
export APP_ENV=development

# For production (stack traces excluded)
export APP_ENV=production  # or unset APP_ENV
```

## References

- [otelsql (raw SQL OpenTelemetry)](https://github.com/nhatthm/otelsql)
- [GORM](https://gorm.io/)
- [GORM OpenTelemetry Plugin](https://github.com/go-gorm/opentelemetry)