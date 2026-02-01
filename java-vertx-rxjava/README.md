# Vert.x RxJava OpenTelemetry Integration with Last9

## Overview

This guide shows how to integrate OpenTelemetry tracing into an existing Vert.x RxJava application and send traces to Last9.

**Important:** The standard OpenTelemetry Java agent does NOT produce HTTP SERVER spans for Vert.x applications. You must use the `vertx-opentelemetry` library.

---

## Step 1: Add Dependencies

Add to your `pom.xml`:

```xml
<properties>
    <opentelemetry.version>1.35.0</opentelemetry.version>
</properties>

<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.opentelemetry</groupId>
            <artifactId>opentelemetry-bom</artifactId>
            <version>${opentelemetry.version}</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<dependencies>
    <!-- Vert.x OpenTelemetry -->
    <dependency>
        <groupId>io.vertx</groupId>
        <artifactId>vertx-opentelemetry</artifactId>
        <version>${vertx.version}</version>
    </dependency>

    <!-- OpenTelemetry SDK -->
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-api</artifactId>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-sdk</artifactId>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-exporter-otlp</artifactId>
    </dependency>

    <!-- Semantic Conventions -->
    <dependency>
        <groupId>io.opentelemetry.semconv</groupId>
        <artifactId>opentelemetry-semconv</artifactId>
        <version>1.23.1-alpha</version>
    </dependency>
</dependencies>
```

---

## Step 2: Initialize OpenTelemetry

Add this initialization code to your main class:

```java
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.semconv.ResourceAttributes;
import io.vertx.core.VertxOptions;
import io.vertx.tracing.opentelemetry.OpenTelemetryOptions;

public class MainApplication {

    public static void main(String[] args) {
        // 1. Initialize OpenTelemetry
        OpenTelemetry openTelemetry = initOpenTelemetry();

        // 2. Create Vert.x with tracing enabled
        VertxOptions vertxOptions = new VertxOptions()
            .setTracingOptions(new OpenTelemetryOptions(openTelemetry));

        Vertx vertx = Vertx.vertx(vertxOptions);

        // 3. Deploy verticles as usual
        vertx.deployVerticle(new MainVerticle());
    }

    private static OpenTelemetry initOpenTelemetry() {
        // Read from environment variables
        String serviceName = System.getenv().getOrDefault("OTEL_SERVICE_NAME", "my-service");
        String environment = System.getenv().getOrDefault("DEPLOYMENT_ENVIRONMENT", "dev");
        String endpoint = System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318");
        String headers = System.getenv().getOrDefault("OTEL_EXPORTER_OTLP_HEADERS", "");

        // Resource with service name and environment
        Resource resource = Resource.getDefault()
            .merge(Resource.create(Attributes.of(
                ResourceAttributes.SERVICE_NAME, serviceName,
                ResourceAttributes.DEPLOYMENT_ENVIRONMENT, environment
            )));

        // OTLP HTTP Exporter
        var exporterBuilder = OtlpHttpSpanExporter.builder()
            .setEndpoint(endpoint + "/v1/traces");

        // Add authorization headers
        if (!headers.isEmpty()) {
            for (String header : headers.split(",")) {
                String[] parts = header.split("=", 2);
                if (parts.length == 2) {
                    exporterBuilder.addHeader(parts[0].trim(), parts[1].trim());
                }
            }
        }

        // Tracer Provider with batch processor
        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
            .addSpanProcessor(BatchSpanProcessor.builder(exporterBuilder.build()).build())
            .setResource(resource)
            .build();

        // Build and register globally
        OpenTelemetrySdk sdk = OpenTelemetrySdk.builder()
            .setTracerProvider(tracerProvider)
            .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
            .buildAndRegisterGlobal();

        // Graceful shutdown
        Runtime.getRuntime().addShutdownHook(new Thread(tracerProvider::close));

        return sdk;
    }
}
```

---

## Step 3: Configure Last9 Credentials

1. Log in to [Last9 Console](https://app.last9.io)
2. Go to **Integrations** → **OpenTelemetry**
3. Copy your endpoint and authorization header

---

## Step 4: Run the Application

```bash
# Build
mvn clean package

# Run with environment variables
export OTEL_SERVICE_NAME=my-service
export DEPLOYMENT_ENVIRONMENT=demo
export OTEL_EXPORTER_OTLP_ENDPOINT=<Last9 endpoint>"
export OTEL_EXPORTER_OTLP_HEADERS="<YOUR_LAST9_TOKEN>"

java -jar target/your-app.jar
```

---

## Local OTel Collector

Instead of sending traces directly to Last9, you can route them through a local OpenTelemetry Collector.

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
  # Transform span name to include url.path (e.g., "GET" -> "GET /v1/holding")
  transform:
    trace_statements:
      - context: span
        statements:
          - set(name, Concat([name, " ", attributes["url.path"]], "")) where attributes["url.path"] != nil

  batch:
    timeout: 5s
    send_batch_size: 100

exporters:
  otlphttp:
    endpoint: https://otlp-aps1.last9.io:443
    headers:
      Authorization: "Basic <YOUR_LAST9_TOKEN>"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [transform, batch]
      exporters: [otlphttp]
```

This transforms span names from `GET` to `GET /v1/holding` using the `url.path` attribute.

### 2. Run the Collector

**Docker:**
```bash
docker run -d --name otel-collector \
  -p 4317:4317 \
  -p 4318:4318 \
  -v $(pwd)/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml \
  otel/opentelemetry-collector-contrib:latest
```

**Binary:**
```bash
otelcol-contrib --config otel-collector-config.yaml
```

### 3. Run the App (pointing to local collector)

```bash
export OTEL_SERVICE_NAME=my-service
export DEPLOYMENT_ENVIRONMENT=demo
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
# No auth headers needed for local collector

java -jar target/your-app.jar
```

### Benefits of Using a Collector

- Centralized configuration for multiple services
- Buffering and retry logic
- Transform/filter traces before export
- Support multiple backends simultaneously

---


## References

- [Vert.x OpenTelemetry Docs](https://vertx.io/docs/vertx-opentelemetry/java/)
- [OpenTelemetry Java SDK](https://opentelemetry.io/docs/languages/java/)
- [Last9 OpenTelemetry Integration](https://last9.io/docs/integrations-opentelemetry/)
