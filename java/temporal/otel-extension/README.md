# Temporal OpenTelemetry Java Agent Extension

Zero-code instrumentation for Temporal Java SDK using OpenTelemetry Java Agent.

## Overview

This extension provides automatic tracing for Temporal workflows and activities without any code changes. It uses ByteBuddy to instrument Temporal SDK classes at runtime.

## Spans Created

| Operation | Span Kind | Target Class |
|-----------|-----------|--------------|
| StartWorkflow | CLIENT | RootWorkflowClientInvoker |
| ExecuteWorkflow | CLIENT | RootWorkflowClientInvoker |
| RunWorkflow | **SERVER** | ReplayWorkflowTaskHandler |
| RunActivity | **SERVER** | POJOActivityTaskHandler |

## Build

```bash
cd otel-extension
mvn clean package
```

## Usage

```bash
# Download OTel Java Agent
curl -L -o opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

# Run with extension
java -javaagent:opentelemetry-javaagent.jar \
     -Dotel.javaagent.extensions=target/temporal-otel-extension-1.0.0.jar \
     -Dotel.service.name=my-temporal-worker \
     -Dotel.exporter.otlp.endpoint=https://otlp.example.com \
     -jar my-temporal-app.jar
```

## Attributes

Each span includes:

| Attribute | Description |
|-----------|-------------|
| `temporal.workflow.type` | Workflow class name |
| `temporal.workflow.id` | Workflow ID |
| `temporal.run.id` | Run ID |
| `temporal.activity.type` | Activity class name |
| `temporal.activity.id` | Activity ID |
| `temporal.operation` | Operation type (START_WORKFLOW, RUN_ACTIVITY, etc.) |
| `rpc.system` | "temporal" |
| `rpc.service` | Service name |
| `rpc.method` | Method name |

## Limitations

1. **Context Propagation**: This PoC does not handle cross-process context propagation. For full trace linking between client and worker, use `temporal-opentracing` module.

2. **Reflection-based extraction**: Activity/workflow metadata is extracted via reflection which may break with SDK updates.

## Production Recommendation

For production use, prefer the manual interceptor approach with `temporal-opentracing` as it:
- Handles context propagation correctly
- Is maintained by Temporal team
- Provides full control over span attributes
