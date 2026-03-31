# NATS Auto-Instrumentation Demo

Zero OTel imports. Full distributed traces.

This demo publishes and subscribes to NATS using the plain Java client. No `import io.opentelemetry` anywhere in the app. Traces come entirely from the [opentelemetry-nats-java](https://github.com/last9/opentelemetry-nats-java) agent extension.

## What you get

- PRODUCER span per `connection.publish()` call
- CONSUMER span per message received — linked to its producer via W3C `traceparent`
- Full OTel messaging semconv: `server.address`, `messaging.client.id`, `messaging.message.body.size`, and more
- NATS server metrics via `prometheus-nats-exporter` → OTel Collector → Last9

## Prerequisites

- Docker and Docker Compose
- Java 17, Maven 3.8+
- Last9 account (get credentials from the Integrations page)

## Quick Start

```bash
# 1. Build the extension JAR
cd ../../../opentelemetry-nats-java
./gradlew assemble

# 2. Download the OTel Java agent
cd -
wget -O opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.10.0/opentelemetry-javaagent.jar

# 3. Build the demo app
mvn clean package -q

# 4. Set credentials
cp .env.example .env
# Edit .env — set OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_HEADERS, LAST9_OTLP_AUTH_HEADER

# 5. Run
docker compose up
```

Open [app.last9.io](https://app.last9.io) → APM → Traces, search for service `nats-auto-demo`. Each publish creates a PRODUCER span linked to a CONSUMER span with the same trace ID.

## Running without Docker

Export credentials first:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-credentials>"
export OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
export OTEL_TRACES_SAMPLER="always_on"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
```

Then:

```bash
mvn clean package -q
java \
  -javaagent:opentelemetry-javaagent.jar \
  -Dotel.javaagent.extensions=../../../opentelemetry-nats-java/build/libs/opentelemetry-nats-java-0.1.0.jar \
  -Dotel.service.name=nats-auto-demo \
  -jar target/nats-auto-demo-1.0.0.jar
```

## Disabling

```bash
-Dotel.instrumentation.nats.enabled=false
```

## How it works

```
java -javaagent:opentelemetry-javaagent.jar
     -Dotel.javaagent.extensions=opentelemetry-nats-java-0.1.0.jar
     -jar nats-auto-demo.jar

ByteBuddy intercepts at class-load time:
  NatsConnection.publishInternal()     → PRODUCER span + injects traceparent into headers
  NatsConnection.createDispatcher()    → wraps the MessageHandler in a TracingMessageHandler

The app calls nats.publish() and receives messages normally.
The agent handles everything else.
```

The lambda handler in `Main.java` is a hidden class — ByteBuddy cannot intercept it directly. Instead, the extension intercepts `createDispatcher()` and wraps the handler before it's stored. Every `onMessage()` call then runs through `TracingMessageHandler`, which extracts trace context and creates the CONSUMER span.
