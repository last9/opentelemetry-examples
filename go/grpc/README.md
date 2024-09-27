# Instrumenting GRPC application using OpenTelemetry

This example demonstrates how to instrument a GRPC application with
OpenTelemetry.

1. After cloning the example, install the required packages using the following
   command:

```bash
go mod tidy
```

2. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

3. Next, run the commands below to set the environment variables. Please set the environment variables for both server and
client applications.

```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
```

4. Run the Server application:

```bash
OTEL_SERVICE_NAME=grpc-server-app go run server/main.go
```

5. Run the Client application:

```bash
OTEL_SERVICE_NAME=grpc-client-app go run client/main.go
2024/09/04 20:19:38 Greeting: Hello
```

6. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM dashboard to see the traces and metrics in action.
