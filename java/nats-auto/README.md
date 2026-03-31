# NATS Auto-Instrumentation Demo

Zero-code OTel tracing for NATS — no `import io.opentelemetry` anywhere in the app.

Traces are produced by the [opentelemetry-nats-java](https://github.com/last9/opentelemetry-nats-java)
agent extension loaded at JVM startup.

## What you get

- **PRODUCER span** for every `connection.publish()` call
- **CONSUMER span** for every `MessageHandler.onMessage()` invocation
- Spans linked across publish/subscribe via W3C `traceparent` header (auto-injected)
- NATS server metrics via `prometheus-nats-exporter` → OTel Collector

## Prerequisites

- Docker and Docker Compose
- Java 17, Maven 3.8+
- Last9 account

## Quick Start

```bash
# 1. Build the extension JAR (from the opentelemetry-nats-java repo)
cd ../../../opentelemetry-nats-java
./gradlew assemble

# 2. Download the OTel Java agent into this directory
cd -
wget -O opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.10.0/opentelemetry-javaagent.jar

# 3. Build the demo app
mvn clean package -q

# 4. Configure credentials
cp .env.example .env
# Edit .env with your Last9 OTLP endpoint and auth header

# 5. Start everything
docker compose up
```

## What to observe in Last9

After `docker compose up`, open [Grafana](https://app.last9.io/grafana):

- **Traces**: search for service `nats-auto-demo` — each publish creates a PRODUCER span
  linked to a CONSUMER span via the same trace ID
- **Metrics**: `gnatsd_varz_in_msgs`, `gnatsd_connz_num_connections`, `gnatsd_routez_*`

## Running without Docker

```bash
mvn clean package -q
java \
  -javaagent:opentelemetry-javaagent.jar \
  -Dotel.javaagent.extensions=../../../opentelemetry-nats-java/build/libs/opentelemetry-nats-java-0.1.0.jar \
  -Dotel.service.name=nats-auto-demo \
  -Dotel.exporter.otlp.endpoint=http://localhost:4318 \
  -Dotel.exporter.otlp.protocol=http/protobuf \
  -jar target/nats-auto-demo-1.0.0.jar
```

## Disabling the instrumentation

```bash
-Dotel.instrumentation.nats.enabled=false
```

## How it works

```
java -javaagent:opentelemetry-javaagent.jar
     -Dotel.javaagent.extensions=opentelemetry-nats-java-0.1.0.jar
     -jar nats-auto-demo.jar

At class-load time, ByteBuddy intercepts:
  NatsConnection.publishInternal()  →  PRODUCER span + injects traceparent header
  MessageHandler.onMessage()        →  CONSUMER span + extracts traceparent header

App code sees none of this — it just uses the NATS client normally.
```
