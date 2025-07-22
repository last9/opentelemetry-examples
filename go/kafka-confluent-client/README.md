# Kafka Hello World in Go

This is a simple Kafka producer and consumer application written in Go that demonstrates basic functionality of Apache Kafka with a "Hello, World!" example.

## Prerequisites

- Go 1.16 or later
- Apache Kafka 2.8.0 or later
- Docker and Docker Compose (optional, for local Kafka setup)

## Installation

1. Install dependencies:
   ```
   go mod download
   ```

## Kafka Setup

### Using Docker (recommended for local development)

You can easily set up Kafka locally using Docker Compose. Create a `docker-compose.yml` file:

```yaml
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.3.0
    container_name: zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    ports:
      - "2181:2181"

  kafka:
    image: confluentinc/cp-kafka:7.3.0
    container_name: kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
```

Start the Kafka cluster:
```
docker compose up -d
```

Create the required topic:
```
docker exec -it kafka kafka-topics --create --topic hello-world-topic --bootstrap-server localhost:9092 --replication-factor 1 --partitions 3
```

### Using an Existing Kafka Installation

If you have an existing Kafka cluster, you need to:

1. Create the required topic:
   ```
   bin/kafka-topics.sh --create --topic hello-world-topic --bootstrap-server localhost:9092 --replication-factor 1 --partitions 3
   ```

2. Update the connection details in both `producer.go` and `consumer.go` to point to your Kafka cluster.

## Running the Application

1. Build and run the consumer:
   ```
   go build -o consumer consumer.go
   ./consumer
   ```

2. In a separate terminal, build and run the producer:
   ```
   go build -o producer producer.go
   ./producer
   ```

The producer will start sending "Hello, World!" messages to the Kafka topic, and the consumer will read and display these messages.

## Application Structure

- `producer.go`: A Kafka producer that sends "Hello, World!" messages to a Kafka topic with incrementing counters.
- `consumer.go`: A Kafka consumer that reads messages from the same topic and prints them to the console.
- `go.mod`: Go module definition with required dependencies.

## Features

- Graceful shutdown of both producer and consumer with SIGINT or SIGTERM signals
- Message delivery reports in the producer
- Proper error handling
- Auto-commit of offsets in the consumer

## Customization

- To change the Kafka broker address, modify the `bootstrap.servers` value in both files
- To use a different topic, change the `topic` variable in both files
- To adjust consumer group settings, modify the `group.id` and other consumer settings

## Troubleshooting

- If you encounter `Failed to create producer/consumer` errors, ensure your Kafka broker is running and accessible
- For network-related issues, check firewall settings and network connectivity
- For authentication errors, ensure you've configured the correct credentials if your Kafka cluster requires authentication

## Further Resources

- [Confluent Kafka Go Client Documentation](https://docs.confluent.io/platform/current/clients/confluent-kafka-go/index.html)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)

## OpenTelemetry Configuration

The application supports the following OpenTelemetry configurations:

### Environment Variables

- `OTEL_EXPORTER_OTLP_ENDPOINT`: The Last9 ingestion endpoint
- `OTEL_SERVICE_NAME`: The name of your service (default: "kafka-hello-world")
- `OTEL_EXPORTER_OTLP_HEADERS`: The Last9 authorization header

### Supported Features

- **Distributed Tracing**: Full support for distributed tracing across producer and consumer
- **Trace Context Propagation**: Automatic propagation of trace context through Kafka messages
- **Semantic Conventions**: Following OpenTelemetry semantic conventions for messaging systems

### Trace Operations

The following operations are traced:

- Producer:
  - `publish`: When a message is published to Kafka

- Consumer:
  - `receive`: When a message is received from Kafka
  - `process`: When a message is being processed