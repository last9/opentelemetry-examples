# Java 8 Agent Compatibility Test

Tests that `vertx3-otel-agent.jar` works correctly on both Java 8 and Java 11+ JVMs. The app is compiled with **Java 8 bytecode** (class file version 52) and exercises every auto-instrumentation advice in the agent.

## What This Tests

| JVM | Expected Behavior |
|-----|-------------------|
| **Java 8** | Agent prints `"Requires Java 11+"` and skips instrumentation. App starts normally — no crash, no `UnsupportedClassVersionError`. |
| **Java 11+** | Agent fully instruments Router, JDBC, Kafka, Aerospike, MySQL, WebClient. Traces exported via shaded OkHttp sender. |

## Quick Start

### 1. Build

```bash
mvn clean package
```

This builds the fat JAR and copies `vertx3-otel-agent.jar` into `target/`.

### 2. Start infrastructure

```bash
docker compose up -d postgres redpanda aerospike
```

### 3. Run with the agent

```bash
export OTEL_SERVICE_NAME=java8-agent-test
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"

java -javaagent:target/vertx3-otel-agent.jar \
     -jar target/vertx3-java8-agent-test-1.0.0.jar
```

### 4. Hit endpoints

```bash
# Router (SERVER spans)
curl http://localhost:8080/ping
curl http://localhost:8080/health

# JDBC / PostgreSQL (CLIENT spans via JdbcClientAdvice)
curl http://localhost:8080/v1/holding
curl -X POST http://localhost:8080/v1/holding \
  -H "Content-Type: application/json" \
  -d '{"userId":"user1","symbol":"AAPL","quantity":10}'

# Kafka (PRODUCER spans via KafkaProducerAdvice)
curl -X POST http://localhost:8080/v1/kafka/produce \
  -H "Content-Type: application/json" \
  -d '{"key":"test-1","value":"{\"msg\":\"hello\"}"}'

# Aerospike (CLIENT spans via AerospikeClientAdvice)
curl -X POST http://localhost:8080/v1/cache/mykey \
  -H "Content-Type: application/json" \
  -d '{"foo":"bar"}'
curl http://localhost:8080/v1/cache/mykey

# WebClient (CLIENT spans via WebClientAdvice)
curl http://localhost:8080/v1/external/post/1

# Multi-system trace (DB + Cache + HTTP + Kafka in one request)
curl http://localhost:8080/v1/portfolio-full/user1
```

### 5. Run the full test suite

```bash
./run-test.sh
```

This runs both:
- **Test 1**: Java 8 Docker container — verifies graceful fallback
- **Test 2**: Local Java 11+ — verifies all instrumentation + Last9 export

## Auto-Instrumented Components

| Component | Span Kind | Agent Advice |
|-----------|-----------|--------------|
| `Router` | SERVER | `RouterImplAdvice` |
| `WebClient` | CLIENT | `WebClientAdvice` |
| `JDBCClient` (PostgreSQL) | CLIENT | `JdbcClientAdvice` |
| `KafkaProducer` | PRODUCER | `KafkaProducerAdvice` |
| `KafkaConsumer` | CONSUMER | `KafkaConsumerAdvice` |
| `AerospikeClient` | CLIENT | `AerospikeClientAdvice` |
| `MySQLPool` | CLIENT | `ReactiveSqlAdvice` |

## Infrastructure (docker-compose.yml)

| Service | Image | Port |
|---------|-------|------|
| PostgreSQL | `postgres:15-alpine` | 5433 |
| Kafka (Redpanda) | `redpanda:v24.1.1` | 9092 |
| MySQL | `mysql:8.0` | 3308 |
| Aerospike | `aerospike-server:7.0.0.4` | 3000 |

## Key Design Decisions

- **Compiled with `maven.compiler.source/target=8`** — simulates a real Java 8 customer app
- **Uses `io.vertx.reactivex.core.AbstractVerticle`** with `rxStart()` — RxJava2 pattern
- **No Java 9+ APIs** — no `var`, no `Set.of()`, no `String.isBlank()`, no diamond-with-anon-class
- **All backends optional** — app starts even if Postgres/Kafka/Aerospike/MySQL are down
- **OpenTelemetry API is `provided` scope** — the agent injects it at runtime, not bundled in the fat JAR
