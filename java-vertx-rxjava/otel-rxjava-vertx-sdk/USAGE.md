# OpenTelemetry RxJava3 Vert.x SDK

A lightweight SDK for proper distributed tracing in RxJava3 + Vert.x applications.

## Features

- **Automatic context propagation** across RxJava3 operators and schedulers
- **Simple span creation** with `Traced.single()`, `Traced.call()`, etc.
- **Log correlation** via MDC (trace_id, span_id in logs)
- **Vert.x integration** with handler utilities

## Installation

### 1. Build and install the SDK

```bash
cd otel-rxjava-vertx-sdk
mvn clean install
```

### 2. Add dependency to your project

```xml
<dependency>
    <groupId>io.otel.rxjava.vertx</groupId>
    <artifactId>otel-rxjava-vertx-sdk</artifactId>
    <version>1.0.0</version>
</dependency>
```

## Quick Start

### 1. Initialize SDK (MainApplication.java)

```java
import io.otel.rxjava.vertx.core.OtelSdk;
import io.vertx.rxjava3.core.Vertx;

public class MainApplication {
    public static void main(String[] args) {
        // Initialize OtelSdk - this enables RxJava context propagation automatically
        OtelSdk sdk = OtelSdk.builder()
                .serviceName("holding-service")
                .environment("production")
                .otlpEndpoint("http://localhost:4318")
                .build();

        // Create Vert.x with tracing enabled
        Vertx vertx = sdk.createVertx();

        // Deploy your verticle
        vertx.deployVerticle(new MainVerticle());
    }
}
```

### 2. Use Traced operations in services

```java
import io.otel.rxjava.vertx.operators.Traced;
import io.reactivex.rxjava3.core.Single;
import java.util.Map;

public class HoldingService {

    public Single<HoldingsResponse> fetchHoldings(String userId, List<String> types) {
        // Creates a child span "HoldingService.fetchHoldings"
        return Traced.call("HoldingService.fetchHoldings",
                Map.of("user.id", userId, "types", types.toString()),
                () -> {
                    log.info("Fetching holdings for user: {}", userId);  // Log will include trace_id
                    return getMockHoldings(types);
                });
    }
}
```

### 3. Chain traced operations in handlers

```java
import io.otel.rxjava.vertx.operators.Traced;
import io.otel.rxjava.vertx.logging.MdcTraceCorrelation;

public void fetchAllHoldings(RoutingContext ctx) {
    // Update MDC at handler entry
    MdcTraceCorrelation.updateMdc();

    String userId = ctx.request().getHeader("X-User-Id");
    log.info("Request received for user: {}", userId);  // Has trace_id!

    // Each service call creates a child span, context propagates through flatMap
    holdingService.fetchHoldings(userId, tradingTypes)
            .flatMap(holdings ->
                graphQLService.enrichHoldings(holdings))  // Child span created
            .subscribe(
                    response -> sendResponse(ctx, response),
                    error -> handleError(ctx, error)
            );
}
```

### 4. Configure logback for trace correlation

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - trace_id=%X{trace_id} span_id=%X{span_id} - %msg%n</pattern>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
</configuration>
```

## API Reference

### OtelSdk

Main SDK initialization class.

```java
// Environment variables (optional - can be configured via builder)
// OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_HEADERS

OtelSdk sdk = OtelSdk.builder()
        .serviceName("my-service")
        .serviceVersion("1.0.0")
        .environment("production")
        .otlpEndpoint("http://localhost:4318")
        .headers("api-key=xxx")  // Optional headers
        .useGrpc(false)          // HTTP by default
        .build();

Vertx vertx = sdk.createVertx();
```

### Traced

Static utility for creating traced RxJava operations.

```java
// Traced Single with callable
Traced.call("spanName", () -> expensiveOperation())

// Traced Single with attributes
Traced.call("spanName", Map.of("key", "value"), () -> operation())

// Traced Single-returning supplier
Traced.single("spanName", () -> repository.findById(id))

// Traced Maybe
Traced.maybe("spanName", () -> cache.get(key))

// Traced Completable
Traced.completable("spanName", () -> publisher.publish(event))

// Traced void operation
Traced.run("spanName", () -> sideEffect())
```

### MdcTraceCorrelation

Log correlation utilities.

```java
// Update MDC with current trace context (call in handlers)
MdcTraceCorrelation.updateMdc();

// Get trace ID for custom logging
String traceId = MdcTraceCorrelation.getTraceId();

// Use MdcScope for scoped operations
try (MdcTraceCorrelation.MdcScope scope = MdcTraceCorrelation.makeCurrent(context)) {
    // MDC populated here
    log.info("This log has trace_id");
}
```

### VertxTracing

Vert.x handler utilities.

```java
// Add attributes to current span
VertxTracing.addAttribute("user.id", userId);
VertxTracing.addAttributes(Map.of("key1", "value1", "key2", "value2"));

// Add events
VertxTracing.addEvent("cache.miss");
VertxTracing.addEvent("validation.complete", Map.of("fields", 5));

// Record exceptions
VertxTracing.recordException(error);

// Create child span manually
Span span = VertxTracing.startSpan("myOperation", Map.of("attr", "value"));
try (Scope scope = span.makeCurrent()) {
    // operation
} finally {
    span.end();
}
```

## Trace Hierarchy Example

With this SDK, a request to `/v1/holding` will produce:

```
HTTP GET /v1/holding (parent - created by vertx-opentelemetry)
├── HoldingService.fetchHoldings (child)
│   └── (logs with trace_id=xxx, span_id=yyy)
└── GraphQLService.enrichHoldings (child)
    └── (logs with trace_id=xxx, span_id=zzz)
```

All logs within these operations will contain the same `trace_id` for correlation.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name for traces | `unknown-service` |
| `OTEL_SERVICE_VERSION` | Service version | `1.0.0` |
| `OTEL_RESOURCE_ATTRIBUTES_DEPLOYMENT_ENVIRONMENT` | Deployment environment | `development` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Headers for OTLP (key=value,key2=value2) | - |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Protocol: `http` or `grpc` | `http` |
