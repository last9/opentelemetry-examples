# Instrumenting Gin application using OpenTelemetry

This example demonstrates how to instrument a simple Gin application with
OpenTelemetry.

1. After cloning the example, install the required packages using the following
   command:

```bash
go mod tidy
```

2. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

3. Next, run the commands below to set the environment variables.

```bash
export OTEL_SERVICE_NAME="gin-app-service"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://ingest.last9.io"
```

4. Run the Gin application:

```bash
go run main.go
```

5. Once the server is running, you can access the application at
   `http://localhost:8080` by default. The API endpoints are:

- GET `/users` - Get all users
- GET `/users/:id` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/:id` - Update a user
- DELETE `/users/:id` - Delete a user

6. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces and metrics in action.
