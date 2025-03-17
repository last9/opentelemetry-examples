# Instrumenting Gin application using OpenTelemetry

This example demonstrates how to instrument a simple Gin application with
OpenTelemetry.

## Prerequisites

- Recent version of Go
- [Last9](https://app.last9.io) account

It uses the following libraries:

- [Gin](https://github.com/gin-gonic/gin)
- [OpenTelemetry](https://github.com/open-telemetry/opentelemetry-go)
- [PostgreSQL](https://github.com/lib/pq)
- [Redis](https://github.com/redis/go-redis/v7)

## Traces

It generates traces for HTTP requests, database queries, Redis commands, and external API calls.

### HTTP requests

- HTTP requests using [otelgin](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/github.com/gin-gonic/gin/otelgin)
- For HTTP requests, wrap the Gin router with the `otelgin.Middleware` middleware. Refer to [main.go](./main.go) for how to do this.

### Database queries

- Database queries using [otelsql](https://github.com/nhatthm/otelsql)
- For database queries, use the `otelsql` package to wrap the `sql.DB` object. Refer to `initDB()` in [users/controller.go](./users/controller.go) for more details.

### Redis commands

- Redis commands using a custom middleware.

### External API calls

- External API calls using [otelhttp](https://github.com/open-telemetry/opentelemetry-go-contrib/tree/main/instrumentation/net/http/otelhttp)
- For external API calls, use the `otelhttp` package to wrap the `http.Client` object. Refer to `getRandomJoke()` in [main.go](./main.go) for more details.

### RabbitMQ Monitoring with OpenTelemetry

#### Overview
This implementation includes OpenTelemetry instrumentation for RabbitMQ operations, providing detailed tracing for message publishing, consumption, and processing flows.

#### Key Features
- Complete trace context propagation through RabbitMQ messages
- Detailed spans for queue operations, message publishing, and consumption
- Job processing spans linked to their parent message operations
- Comprehensive messaging system attributes for better observability

#### 1. Message Broker Interface
```go
type MessageBroker interface {
    PublishMessage(ctx context.Context, queueName string, data []byte) error
    ConsumeMessages(ctx context.Context, queueName string) (<-chan Message, error)
    AckMessage(ctx context.Context, msg *amqp.Delivery) error
    NackMessage(ctx context.Context, msg *amqp.Delivery, requeue bool) error
}
```

#### 2. Trace Context Propagation
The implementation automatically handles trace context propagation:
- Injects trace context into message headers during publishing
- Extracts and continues trace context during message consumption
- Maintains parent-child relationship between spans

#### 3. Monitored Operations
Each operation creates its own span with detailed attributes:

- Queue Declaration:
  ```go
  // Attributes included:
  - messaging.system: "rabbitmq"
  - messaging.destination: <queue_name>
  - messaging.destination_kind: "queue"
  - messaging.operation: "declare"
  ```

- Message Publishing:
  ```go
  // Attributes included:
  - messaging.system: "rabbitmq"
  - messaging.destination: <queue_name>
  - messaging.destination_kind: "queue"
  - messaging.protocol: "AMQP"
  - messaging.protocol_version: "0.9.1"
  - messaging.operation: "publish"
  - messaging.message_size: <size_in_bytes>
  ```

- Message Consumption:
  ```go
  // Attributes included:
  - messaging.system: "rabbitmq"
  - messaging.destination: <queue_name>
  - messaging.destination_kind: "queue"
  - messaging.operation: "process"
  - messaging.message_id: <message_id>
  - messaging.conversation_id: <correlation_id>
  ```

#### 3. Message Acknowledgment:
```go
// Acknowledge successful processing
broker.AckMessage(ctx, msg.Original)

// For failed processing
broker.NackMessage(ctx, msg.Original, shouldRequeue)
```
### Instrumentation packages

Following packages are used to instrument the Gin application. You can install them using the following commands:

```sh
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin
go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
go get go.opentelemetry.io/otel/sdk
go get go.opentelemetry.io/otel/sdk/metric
go get go.opentelemetry.io/otel/trace
go get go.nhat.io/otelsql
```

## Metrics

It also generates metrics for database queries using [otelsql](https://github.com/nhatthm/otelsql)

## Exporting Telemetry Data to Last9

It uses GRPC exporters to export the traces and metrics to Last9. You can also use any other OpenTelemetry compatible backend.

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
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io" # or your endpoint
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
