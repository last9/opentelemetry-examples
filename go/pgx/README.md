# Instrumenting Gin application using OpenTelemetry with pgx and otelpgx

This example demonstrates how to instrument a simple Gin application with OpenTelemetry, using [pgx](https://github.com/jackc/pgx) for PostgreSQL database operations and [otelpgx](https://github.com/exaring/otelpgx) for database call instrumentation.

## Prerequisites

- Recent version of Go
- pgx v5+
- PostgreSQL database
- [Last9](https://app.last9.io) account (or any other OpenTelemetry compatible backend)

It uses the following libraries:

- [Gin](https://github.com/gin-gonic/gin) for the web framework
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go) for instrumentation
- [pgx](https://github.com/jackc/pgx) for PostgreSQL operations
- [otelpgx](https://github.com/exaring/otelpgx) for instrumenting pgx database calls

## Traces

It generates traces for the following:

- HTTP requests using [otelgin](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/github.com/gin-gonic/gin/otelgin)
- Database queries using [otelpgx](https://github.com/exaring/otelpgx)

### HTTP Request Instrumentation

For HTTP requests, we wrap the Gin router with the `otelgin.Middleware` middleware. Refer to [main.go](main.go) for how to do this:

### Database Instrumentation

For database instrumentation, we use [otelpgx](https://github.com/exaring/otelpgx) to wrap the pgx connection pool. Refer to [main.go](main.go) for how to do this:

```go
	var connString = os.Getenv("DATABASE_URL")
	cfg, err := pgxpool.ParseConfig(connString)
	if err != nil {
		fmt.Fprintf(os.Stderr, "create connection pool: %w", err)
		os.Exit(1)
	}

    // Add the tracer to the connection pool configuration
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
    // Create a new connection pool with the tracer
	conn, err = pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connection to database: %v\n", err)
		os.Exit(1)
	}
```

## Exporting traces to Last9

It uses GRPC exporters to export the traces and metrics to Last9. You can also use any other OpenTelemetry compatible backend.

## Running the application

1. After cloning the example, install the required packages using the following
   command:

```bash
go mod tidy
```

2. Setup the database

```sh
createdb todo
psql todo < structure.sql
```

Export the database name as `PGDATABASE` environment variable.

```sh
export PGDATABASE="todo"
```

3. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

4. Next, run the commands below to set the environment variables.

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your endpoint 
```

5. Run the Gin application:

```bash
go build -o gin && ./gin
```

6. Once the server is running, you can access the application at
   `http://localhost:8080` by default. The API endpoints are:

- GET `/tasks` - Get all tasks
- POST `/tasks` - Create a new task

6. Sign in to [Last9](https://app.last9.io) and visit the APM dashboard to see the traces.
