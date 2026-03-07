# Temporal Java OpenTelemetry Instrumentation

A sample order processing workflow demonstrating OpenTelemetry tracing with Temporal Java SDK.

## How to Instrument Java Temporal Apps

### 1. Add Dependencies

Add the Temporal OpenTracing module and OpenTelemetry shim to your `pom.xml`:

```xml
<!-- Temporal OpenTracing Module -->
<dependency>
    <groupId>io.temporal</groupId>
    <artifactId>temporal-opentracing</artifactId>
    <version>1.26.0</version>
</dependency>

<!-- OpenTelemetry SDK -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-sdk</artifactId>
    <version>1.44.1</version>
</dependency>

<!-- OpenTelemetry OTLP Exporter -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
    <version>1.44.1</version>
</dependency>

<!-- OpenTracing to OpenTelemetry Bridge -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-opentracing-shim</artifactId>
    <version>1.44.1</version>
</dependency>
```

### 2. Initialize OpenTelemetry with OpenTracing Shim

Temporal uses OpenTracing interceptors. Bridge them to OpenTelemetry:

```java
import io.opentelemetry.opentracingshim.OpenTracingShim;
import io.opentracing.util.GlobalTracer;

// Build OpenTelemetry SDK
OtlpGrpcSpanExporter exporter = OtlpGrpcSpanExporter.builder()
        .setEndpoint("http://localhost:4317")
        .build();

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
        .addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
        .setResource(Resource.create(Attributes.of(
                ResourceAttributes.SERVICE_NAME, "your-service")))
        .build();

OpenTelemetrySdk otelSdk = OpenTelemetrySdk.builder()
        .setTracerProvider(tracerProvider)
        .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
        .build();

// Create OpenTracing shim and register globally
Tracer tracer = OpenTracingShim.createTracerShim(otelSdk);
GlobalTracer.registerIfAbsent(tracer);
```

### 3. Add Interceptors to Workflow Client

```java
WorkflowClient client = WorkflowClient.newInstance(
        service,
        WorkflowClientOptions.newBuilder()
                .setInterceptors(new OpenTracingClientInterceptor())
                .build()
);
```

### 4. Add Interceptors to Worker Factory

```java
WorkerFactory factory = WorkerFactory.newInstance(
        client,
        WorkerFactoryOptions.newBuilder()
                .setWorkerInterceptors(new OpenTracingWorkerInterceptor())
                .build()
);
```

## Running the Sample

### Prerequisites

- Java 17+
- Maven 3.6+
- Docker and Docker Compose

### Quick Start

1. **Copy environment file**
   ```bash
   cp .env.example .env
   # Edit .env with your Last9 credentials
   ```

2. **Start infrastructure**
   ```bash
   docker compose up -d
   ```

3. **Build the project**
   ```bash
   mvn clean compile
   ```

4. **Start the worker** (Terminal 1)
   ```bash
   mvn exec:java -Dexec.mainClass="io.temporal.example.worker.OrderWorker"
   ```

5. **Run a workflow** (Terminal 2)
   ```bash
   mvn exec:java -Dexec.mainClass="io.temporal.example.worker.OrderStarter"
   ```

6. **View traces** in [Last9 dashboard](https://app.last9.io)

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPORAL_ADDRESS` | `localhost:7233` | Temporal server address |
| `OTEL_SERVICE_NAME` | `temporal-order-service` | Service name in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | OTLP collector endpoint |

### Temporal UI

Access workflow visualization at http://localhost:8080
