# Scala + Akka HTTP OpenTelemetry Example

A portfolio service demonstrating OpenTelemetry instrumentation for Scala 3 applications using [Apache Pekko HTTP](https://pekko.apache.org/docs/pekko-http/current/) (drop-in replacement for Akka HTTP). Exports traces, metrics, and logs to [Last9](https://last9.io) via an OpenTelemetry Collector.

> **Akka HTTP users**: Replace `org.apache.pekko` with `com.typesafe.akka` in `build.sbt` and adjust versions. The API is identical.

## What's Instrumented

| Integration | Method | Signals |
|-------------|--------|---------|
| Pekko HTTP server routes | Manual spans | Traces |
| PostgreSQL (HikariCP + JDBC) | OTel Java Agent (auto) | Traces |
| Redis (Lettuce) | OTel Java Agent (auto) | Traces |
| Kafka producer | OTel Java Agent (auto) | Traces |
| Aerospike client | Manual spans | Traces |
| HTTP client (outbound) | OTel Java Agent (auto) | Traces |
| JVM metrics (GC, heap, threads) | OTel Java Agent (auto) | Metrics |
| Application logs | Logback `OpenTelemetryAppender` | Logs |

## Prerequisites

- Docker and Docker Compose
- [Last9](https://app.last9.io) account for OTLP credentials

## Quick Start

1. **Clone and configure**

   ```bash
   cp .env.example .env
   # Edit .env — set LAST9_OTLP_ENDPOINT and LAST9_OTLP_AUTH_HEADER
   ```

2. **Start everything**

   ```bash
   docker-compose up --build
   ```

3. **Generate traffic**

   ```bash
   # Create a portfolio
   curl -X POST http://localhost:8080/portfolios \
     -H 'Content-Type: application/json' \
     -d '{"name":"Tech Fund","userId":"user-1","balance":10000}'

   # List portfolios
   curl http://localhost:8080/portfolios

   # Get a portfolio (checks Redis cache)
   curl http://localhost:8080/portfolios/1

   # Get price (HTTP client call with trace propagation)
   curl http://localhost:8080/portfolios/1/price

   # Aerospike fast-lookup
   curl http://localhost:8080/portfolios/1/aerospike
   ```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `APP_PORT` | `8080` | HTTP server port |
| `POSTGRES_URL` | `jdbc:postgresql://localhost:5432/portfoliodb` | JDBC connection URL |
| `REDIS_HOST` / `REDIS_PORT` | `localhost:6379` | Redis address |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka brokers |
| `AEROSPIKE_HOST` / `AEROSPIKE_PORT` | `localhost:3000` | Aerospike node |
| `OTEL_SERVICE_NAME` | `portfolio-service` | Service name in traces |
| `LAST9_OTLP_ENDPOINT` | — | From Last9 dashboard |
| `LAST9_OTLP_AUTH_HEADER` | — | `Basic <credentials>` |

## How It Works

```
Application
    │
    ├── Pekko HTTP server ──► manual spans (SpanKind.SERVER)
    ├── PostgreSQL (JDBC) ──► auto-instrumented by OTel Java Agent
    ├── Redis (Lettuce)   ──► auto-instrumented by OTel Java Agent
    ├── Kafka producer    ──► auto-instrumented + W3C header injection
    ├── Aerospike         ──► manual spans (SpanKind.CLIENT)
    └── HTTP client       ──► auto-instrumented + W3C header propagation
           │
           ▼ OTLP (HTTP/protobuf)
    OTel Collector
           │
           ▼ OTLP (HTTP/protobuf)
        Last9
```

The OTel Java Agent (`-javaagent:otel-javaagent.jar`) instruments JDBC, Lettuce, and Kafka-clients at JVM startup via bytecode instrumentation — no code changes required for those integrations.

## Verification

After sending requests, check the OTel Collector logs to confirm telemetry is flowing:

```bash
docker logs akka-http-otel-collector 2>&1 | grep -E "traces|metrics|logs"
```

Then open [Last9](https://app.last9.io) to view traces, metrics, and correlated logs.

## MySQL Support

MySQL works identically to PostgreSQL — the OTel Java Agent instruments any JDBC driver. Swap the driver dependency in `build.sbt` and update the `POSTGRES_URL` to a MySQL JDBC URL (`jdbc:mysql://...`).
