# Vert.x 3 RxJava2 — Zero-Code OpenTelemetry with `-javaagent`

Zero-code OpenTelemetry tracing for Vert.x 3 + RxJava2 applications. No code changes required — just add `-javaagent:vertx3-otel-agent.jar` to your JVM args and the agent automatically instruments everything.

## How It Works

The `vertx3-otel-agent.jar` is a self-contained Java agent that uses ByteBuddy to intercept Vert.x internals at class-load time. **Your application code stays completely untouched** — no `TracedRouter`, no `OtelLauncher`, no OpenTelemetry dependency needed.

```
┌─────────────────────────────────────────────────────────┐
│  java -javaagent:vertx3-otel-agent.jar -jar my-app.jar │
│                                                         │
│  Agent auto-instruments:                                │
│  ├── Router          → SERVER spans (HTTP routes)       │
│  ├── WebClient       → CLIENT spans + traceparent       │
│  ├── JDBCClient      → CLIENT spans (SQL queries)       │
│  ├── KafkaProducer   → PRODUCER spans                   │
│  ├── KafkaConsumer   → CONSUMER spans                   │
│  ├── AerospikeClient → CLIENT spans (cache ops)         │
│  ├── MySQLPool       → CLIENT spans (reactive SQL)      │
│  ├── Jedis/Lettuce   → CLIENT spans (Redis)             │
│  └── Netty HTTP      → CLIENT spans (raw HTTP)          │
│                                                         │
│  Exports via OkHttp OTLP sender (Java 8+ compatible)    │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Java 8+ (agent gracefully skips instrumentation on Java 8, fully instruments on Java 11+)
- Maven 3.6+
- Docker & Docker Compose (for infrastructure)
- [Last9](https://last9.io) account (or any OTLP-compatible backend)

## Quick Start

### 1. Get the agent JAR

Download from [releases](https://github.com/last9/vertx-opentelemetry/releases) or build from source:

```bash
# From the vertx-rxjava3-otel-autoconfigure repo
mvn clean package -pl vertx3-otel-agent -am
cp vertx3-otel-agent/target/vertx3-otel-agent-*.jar ./vertx3-otel-agent.jar
```

### 2. Build your app (no OTel dependency needed)

```bash
mvn clean package
```

### 3. Run with the agent

```bash
export OTEL_SERVICE_NAME=holding-service
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"

java -javaagent:vertx3-otel-agent.jar \
     -jar target/your-app.jar
```

That's it. Every Router endpoint, JDBC query, Kafka message, Aerospike operation, and outbound HTTP call is automatically traced.

### 4. Start infrastructure and test

```bash
# Start Postgres, Kafka, Aerospike, MySQL
docker compose up -d

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/v1/holding
curl -X POST http://localhost:8080/v1/holding \
  -H "Content-Type: application/json" \
  -d '{"userId": "user1", "symbol": "AAPL", "quantity": 100}'
curl http://localhost:8080/v1/portfolio-full/user1
```

## What Gets Auto-Traced

| Component | Span Kind | Agent Advice | Attributes |
|-----------|-----------|--------------|------------|
| `Router` | SERVER | `RouterImplAdvice` | `http.method`, `http.route`, `http.status_code` |
| `WebClient` | CLIENT | `WebClientAdvice` | `http.method`, `net.peer.name`, `http.status_code` |
| `JDBCClient` | CLIENT | `JdbcClientAdvice` | `db.system`, `db.statement`, `db.name` |
| `KafkaProducer` | PRODUCER | `KafkaProducerAdvice` | `messaging.system`, `messaging.destination` |
| `KafkaConsumer` | CONSUMER | `KafkaConsumerAdvice` | `messaging.system`, `messaging.destination` |
| `AerospikeClient` | CLIENT | `AerospikeClientAdvice` | `db.system`, `db.operation`, `db.name` |
| `MySQLPool` | CLIENT | `ReactiveSqlAdvice` | `db.system`, `db.statement`, `net.peer.name` |
| `Jedis` / `Lettuce` | CLIENT | `JedisAdvice` / `LettuceAdvice` | `db.system=redis`, `db.statement` |

## Java 8 Compatibility

The agent works on **Java 8+** JVMs:

- **Java 8**: Agent detects the JVM version, prints `"Requires Java 11+"`, and **skips instrumentation**. Your app starts normally with zero overhead.
- **Java 11+**: Full instrumentation. Traces exported via OkHttp OTLP sender (shaded to avoid classpath conflicts).

This means you can ship `vertx3-otel-agent.jar` bundled with your deployment — it's safe to attach on any JVM version.

## Configuration

All configuration is via standard OpenTelemetry environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name in traces | `unknown_service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint URL | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers (e.g. `Authorization=Basic ...`) | — |
| `OTEL_TRACES_SAMPLER` | Sampling strategy | `parentbased_always_on` |
| `OTEL_RESOURCE_ATTRIBUTES` | Extra resource attributes | — |

Application-specific variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_PORT` | HTTP server port | `8080` |
| `POSTGRES_HOST` / `POSTGRES_PORT` | PostgreSQL connection | `localhost:5432` |
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka brokers | `localhost:9092` |
| `AEROSPIKE_HOST` / `AEROSPIKE_PORT` | Aerospike connection | `localhost:3000` |
| `MYSQL_HOST` / `MYSQL_PORT` | MySQL connection | `localhost:3306` |

## API Endpoints

| Method | Path | Description | Auto-Traced By |
|--------|------|-------------|----------------|
| GET | `/health` | Health check | Router |
| GET | `/v1/holding` | List all holdings | Router + JDBC |
| GET | `/v1/holding/:userId` | Get user holdings | Router + JDBC |
| POST | `/v1/holding` | Create holding | Router + JDBC |
| DELETE | `/v1/holding/:id` | Delete holding | Router + JDBC |
| GET | `/v1/portfolio/:userId` | Portfolio with pricing | Router + JDBC + WebClient |
| GET | `/v1/external/joke` | External API call | Router + WebClient |
| POST | `/v1/kafka/produce` | Produce Kafka message | Router + Kafka Producer |
| POST | `/v1/kafka/produce-batch` | Batch produce | Router + Kafka Producer |
| POST | `/v1/cache/:key` | Cache put | Router + Aerospike |
| GET | `/v1/cache/:key` | Cache get | Router + Aerospike |
| DELETE | `/v1/cache/:key` | Cache delete | Router + Aerospike |
| GET | `/v1/mysql/ping` | MySQL health | Router + MySQL |
| GET | `/v1/portfolio-full/:userId` | Multi-system query | Router + JDBC + Aerospike + WebClient + Kafka |
| GET | `/v1/error/http` | Error scenario | Router (exception recording) |
| GET | `/v1/error/try-catch` | Manual span error | Router + `Span.recordException()` |

## Key Difference: Zero-Code vs Manual

| | Zero-Code (`-javaagent`) | Manual (TracedRouter/OtelLauncher) |
|---|---|---|
| **Code changes** | None | Replace Router, change Launcher |
| **Dependencies** | None (agent is external) | Add library to pom.xml |
| **Scope** | All supported components | Only what you wrap |
| **Java version** | 8+ (graceful skip on 8) | 11+ |
| **Recommended** | **Yes** | Legacy only |

## Resources

- [Last9 OpenTelemetry Docs](https://docs.last9.io/docs/opentelemetry)
- [Vert.x 3 Documentation](https://vertx.io/docs/3.9.16/)
- [vertx-opentelemetry GitHub](https://github.com/last9/vertx-opentelemetry)
