# Vert.x RxJava3 OpenTelemetry Integration

Integrate OpenTelemetry tracing and logging into Vert.x RxJava3 applications with **automatic context propagation**, **log correlation**, **PostgreSQL tracing**, and **OTLP log export**.

> **Note:** The standard OpenTelemetry Java agent does NOT produce HTTP SERVER spans for Vert.x. Use the `otel-rxjava-vertx-sdk` provided in this repo.

---

## Quick Start

### 1. Add the SDK Dependency

First, build and install the SDK:

```bash
cd otel-rxjava-vertx-sdk
mvn clean install
```

Add to your `pom.xml`:

```xml
<dependency>
    <groupId>io.otel.rxjava.vertx</groupId>
    <artifactId>otel-rxjava-vertx-sdk</artifactId>
    <version>1.0.0</version>
</dependency>
```

### 2. Initialize the SDK

Replace your existing Vert.x initialization:

```java
import io.otel.rxjava.vertx.core.OtelSdk;
import io.vertx.rxjava3.core.Vertx;

public class MainApplication {
    public static void main(String[] args) {
        // Initialize SDK - sends to local OTel collector by default
        OtelSdk sdk = OtelSdk.builder()
                .serviceName("my-service")
                .environment("demo")
                .otlpEndpoint("http://localhost:4318")  // Local collector
                .build();

        // Create Vert.x with tracing enabled
        Vertx vertx = sdk.createVertx();

        vertx.deployVerticle(new MainVerticle());
    }
}
```

### 3. Add Tracing to Services

Use `Traced.call()` to create spans for service methods:

```java
import io.otel.rxjava.vertx.operators.Traced;
import java.util.Map;

public class UserService {

    public Single<User> getUser(String userId) {
        return Traced.call(
            "UserService.getUser",
            Map.of("user.id", userId),
            () -> repository.findById(userId)
        );
    }
}
```

### 4. Add Log Correlation and Export

Add the logback appender dependency to `pom.xml`:

```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-logback-appender-1.0</artifactId>
    <version>2.4.0-alpha</version>
</dependency>
```

Update `logback.xml` to include trace context and OTLP export:

```xml
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} %-5level %logger{36} - trace_id=%X{trace_id} span_id=%X{span_id} - %msg%n</pattern>
        </encoder>
    </appender>

    <appender name="OTEL" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
        <captureExperimentalAttributes>true</captureExperimentalAttributes>
        <captureMdcAttributes>*</captureMdcAttributes>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="OTEL"/>
    </root>
</configuration>
```

In handlers, call `MdcTraceCorrelation.updateMdc()`:

```java
import io.otel.rxjava.vertx.logging.MdcTraceCorrelation;

public void handleRequest(RoutingContext ctx) {
    MdcTraceCorrelation.updateMdc();  // Populates MDC with trace_id/span_id
    log.info("Processing request");   // This log will have trace context
    // ...
}
```

---

## Local OTel Collector Setup

### 1. Create Collector Config

Create `otel-collector-config.yaml`:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  # Transform span names: "GET" -> "GET /v1/holding"
  transform:
    trace_statements:
      - context: span
        statements:
          - set(name, Concat([name, " ", attributes["url.path"]], "")) where attributes["url.path"] != nil

  batch:
    timeout: 5s
    send_batch_size: 100

exporters:
  # Export to your observability backend (via env vars)
  otlphttp:
    endpoint: ${OTLP_ENDPOINT}
    headers:
      Authorization: "${OTLP_AUTH_HEADER}"

  # Debug output (optional)
  debug:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [transform, batch]
      exporters: [otlphttp, debug]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp, debug]
```

### 2. Run the Collector

```bash
docker run -d --name otel-collector \
  -p 4317:4317 -p 4318:4318 \
  -v $(pwd)/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml \
  -e OTLP_ENDPOINT="https://otlp.your-backend.io:443" \
  -e OTLP_AUTH_HEADER="Basic <YOUR_TOKEN>" \
  otel/opentelemetry-collector-contrib:latest
```

### 3. Run the Application

```bash
export OTEL_SERVICE_NAME=holding-service
export DEPLOYMENT_ENV=demo
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

java -jar target/your-app.jar
```

---

## SDK Components

| Component | Purpose |
|-----------|---------|
| `OtelSdk` | Initialize OpenTelemetry and create traced Vert.x instance |
| `Traced.call()` | Create child spans for sync operations |
| `Traced.single()` | Create child spans for RxJava Single operations |
| `MdcTraceCorrelation` | Populate MDC with trace_id/span_id for log correlation |
| `VertxTracing` | Add attributes/events to current span |

---

## Trace Hierarchy Example

Request to `/v1/holding/db` produces:

```
GET /v1/holding/db                              (HTTP span)
├── HoldingService.fetchHoldingsFromDb          (child)
│   └── PostgresRepository.fetchByUserAndTypes  (child)
│       └── db.system=postgresql
└── GraphQLService.enrichHoldings               (child)
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name | `unknown-service` |
| `DEPLOYMENT_ENV` | Environment (dev/staging/prod) | `development` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Collector endpoint | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers (key=value) | - |

---

## API Reference

### Traced Operations

```java
// Sync callable -> Single
Traced.call("spanName", () -> doWork())
Traced.call("spanName", Map.of("key", "value"), () -> doWork())

// RxJava Single
Traced.single("spanName", () -> repository.find())

// RxJava Completable
Traced.completable("spanName", () -> publisher.publish())

// Void operation -> Completable
Traced.run("spanName", () -> sideEffect())
```

### Span Attributes & Events

```java
// Add attributes to current span
VertxTracing.addAttribute("user.id", userId);
VertxTracing.addAttributes(Map.of("key1", "val1", "key2", "val2"));

// Add events
VertxTracing.addEvent("cache.miss");
VertxTracing.addEvent("validation.complete", Map.of("fields", 5));

// Record exceptions
VertxTracing.recordException(error);
```

---

## PostgreSQL Integration

Add the Vert.x PG client:

```xml
<dependency>
    <groupId>io.vertx</groupId>
    <artifactId>vertx-pg-client</artifactId>
    <version>${vertx.version}</version>
</dependency>
<dependency>
    <groupId>com.ongres.scram</groupId>
    <artifactId>client</artifactId>
    <version>2.1</version>
</dependency>
```

Wrap DB calls with `Traced.single()`:

```java
public Single<List<User>> findAll() {
    return Traced.single(
        "UserRepository.findAll",
        Map.of("db.system", "postgresql"),
        () -> pgPool.query("SELECT * FROM users").rxExecute()
                .map(this::mapRows)
    );
}
```

---

## Project Structure

```
java-vertx-rxjava/
├── otel-rxjava-vertx-sdk/          # Reusable SDK
│   └── src/main/java/io/otel/rxjava/vertx/
│       ├── core/OtelSdk.java
│       ├── operators/Traced.java
│       ├── operators/RxJava3ContextPropagation.java
│       ├── logging/MdcTraceCorrelation.java
│       └── context/VertxTracing.java
├── src/                             # Example application
├── otel-collector-config.yaml       # Collector config
└── pom.xml
```

---

## References

- [Vert.x OpenTelemetry](https://vertx.io/docs/vertx-opentelemetry/java/)
- [OpenTelemetry Java SDK](https://opentelemetry.io/docs/languages/java/)
- [OTel Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
