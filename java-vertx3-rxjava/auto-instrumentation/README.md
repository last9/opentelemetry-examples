# Vert.x 3 RxJava2 OpenTelemetry Auto-Instrumentation Example

Production-ready OpenTelemetry auto-instrumentation for Vert.x 3 applications using RxJava2. Zero-code tracing with automatic span creation for HTTP requests, database queries, and distributed traces.

## Prerequisites

- Java 11+
- Maven 3.6+
- Docker & Docker Compose
- Last9 account (for observability backend)

## Quick Start

### 1. Download the auto-instrumentation JAR

```bash
curl -L -o vertx3-rxjava2-otel-autoconfigure-1.0.0.jar \
  https://github.com/last9/vertx-opentelemetry/releases/download/v1.0.0/vertx3-rxjava2-otel-autoconfigure-1.0.0.jar
```

### 2. Install JAR to local Maven repository

```bash
mvn install:install-file \
  -Dfile=vertx3-rxjava2-otel-autoconfigure-1.0.0.jar \
  -DgroupId=io.last9 \
  -DartifactId=vertx3-rxjava2-otel-autoconfigure \
  -Dversion=1.0.0 \
  -Dpackaging=jar
```

### 3. Configure environment

```bash
cp .env.example .env
# Edit .env with your Last9 credentials
```

### 4. Start with Docker Compose

```bash
docker-compose up --build
```

### 5. Test the API

```bash
# Health check
curl http://localhost:8080/health

# Create a holding
curl -X POST http://localhost:8080/v1/holding \
  -H "Content-Type: application/json" \
  -d '{"userId": "user1", "symbol": "AAPL", "quantity": 100}'

# Get portfolio with pricing (distributed trace)
curl http://localhost:8080/v1/portfolio/user1
```

## Local Development (without Docker)

### 1. Start PostgreSQL

```bash
docker run -d --name postgres-vertx3 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=holdingdb \
  -p 5432:5432 \
  postgres:15-alpine
```

### 2. Build and run

```bash
mvn clean package

# Run pricing service
OTEL_SERVICE_NAME=pricing-service \
APP_PORT=8081 \
java -jar target/vertx3-rxjava2-otel-example-1.0.0.jar run com.example.pricing.PricingVerticle

# Run holding service (in another terminal)
OTEL_SERVICE_NAME=holding-service \
APP_PORT=8080 \
java -jar target/vertx3-rxjava2-otel-example-1.0.0.jar run com.example.holding.MainVerticle
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_PORT` | HTTP server port | `8080` |
| `POSTGRES_HOST` | PostgreSQL host | `localhost` |
| `POSTGRES_PORT` | PostgreSQL port | `5432` |
| `POSTGRES_DB` | Database name | `holdingdb` |
| `POSTGRES_USER` | Database user | `postgres` |
| `POSTGRES_PASSWORD` | Database password | `postgres` |
| `PRICING_SERVICE_URL` | Pricing service URL | `http://localhost:8081` |
| `OTEL_SERVICE_NAME` | Service name in traces | `vertx3-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | `http://localhost:4318` |

## How It Works

### Auto-Instrumentation Setup

1. **Launcher**: The JAR provides `io.last9.tracing.otel.v3.OtelLauncher` as the main class, which initializes OpenTelemetry before starting Vert.x

2. **TracedRouter**: Replace `Router.router(vertx)` with `TracedRouter.create(vertx)` for automatic HTTP span creation with route patterns

3. **Log Correlation**: Configure `logback.xml` with `MdcTraceTurboFilter` to inject `trace_id` and `span_id` into logs

### What Gets Traced

- HTTP server requests (method, route, status code)
- Database queries (SQL statements, connection info)
- HTTP client calls (downstream services)
- RxJava2 context propagation across operators

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/v1/holding` | List all holdings |
| GET | `/v1/holding/:userId` | Get user's holdings |
| POST | `/v1/holding` | Create holding |
| DELETE | `/v1/holding/:id` | Delete holding |
| GET | `/v1/portfolio/:userId` | Get portfolio with prices |

## Vert.x 3 vs Vert.x 4

| Feature | Vert.x 3 | Vert.x 4 |
|---------|----------|----------|
| Java Version | 11+ | 17+ |
| RxJava | RxJava 2 | RxJava 3 |
| Database Client | JDBC Client | Reactive PG Client |
| Launcher | `io.last9.tracing.otel.v3.OtelLauncher` | `io.last9.tracing.otel.v4.OtelLauncher` |
| TracedRouter | `io.last9.tracing.otel.v3.TracedRouter` | `io.last9.tracing.otel.v4.TracedRouter` |

## Resources

- [Last9 OpenTelemetry Docs](https://docs.last9.io/docs/opentelemetry)
- [Vert.x 3 Documentation](https://vertx.io/docs/3.9.16/)
- [vertx-opentelemetry GitHub](https://github.com/last9/vertx-opentelemetry)
