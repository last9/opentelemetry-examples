# Instrumenting Java Applications using OpenTelemetry Operator in Kubernetes

This example demonstrates how to integrate OpenTelemetry tracing with Java applications using the OpenTelemetry Operator in Kubernetes. The implementation provides distributed tracing for HTTP requests, database calls, and external API interactions.

## Prerequisites

- Kubernetes cluster (tested with K3s v1.32.6)
- kubectl configured to access your cluster
- Helm 3.x installed
- [Last9](https://app.last9.io) account

It uses the following components:

- [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator)
- [OpenTelemetry Java Auto-instrumentation](https://github.com/open-telemetry/opentelemetry-java-instrumentation)

## Traces

It generates traces for:

- HTTP requests using OpenTelemetry auto-instrumentation
- Database calls and external API calls
- JVM metrics and application metrics
- Kubernetes resource attributes

### HTTP Requests

- HTTP requests are automatically instrumented using the OpenTelemetry Java agent
- No code changes required for basic HTTP tracing
- Supports Spring Boot, Spring MVC, and other popular Java frameworks

### Database and External API Calls

- Database connections (JDBC, JPA, Hibernate) are automatically instrumented
- HTTP client libraries (OkHttp, Apache HttpClient) are auto-instrumented
- Message queue operations (RabbitMQ, Kafka) are traced automatically

### Instrumentation Components

The following components are automatically injected by the operator:

- OpenTelemetry Java Agent
- Auto-instrumentation for popular Java libraries
- Resource detection for Kubernetes environment
- Metric collection for JVM and application metrics

## Installation

1. Clone or download the project files
2. Install the OpenTelemetry Operator:

```bash
# Add the OpenTelemetry Helm repository
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Install cert-manager (required dependency)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s

# Install OpenTelemetry Operator
helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --set "manager.collectorImage.repository=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s" \
  --wait
```

3. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

4. Update the `OpenTelemetryCollector.yaml` file with your Last9 credentials:

```yaml
exporters:
  otlp:
    endpoint: "https://otlp-aps1.last9.io:443"
    headers:
      authorization: "Basic <YOUR_BASIC_AUTH_TOKEN>"
```

## Configuration

### Environment Variables

The instrumentation automatically sets the following environment variables for your Java applications:

```bash
# Service identification
OTEL_SERVICE_NAME=java-sample-app
OTEL_SERVICE_VERSION=1.0.0

# Exporter endpoints
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://otel-collector:4318/v1/metrics
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://otel-collector:4318/v1/logs

# Exporter configuration
OTEL_LOGS_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_TRACES_EXPORTER=otlp
```

### Optional Resource Attributes

You can customize service attributes by modifying the `instrumentation.yaml`:

```yaml
env:
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: service.name=my-java-api,service.version=2.0.0,deployment.environment=production
```

## Running the Application

1. Deploy the OpenTelemetry Collector:

```bash
kubectl apply -f OpenTelemetryCollector.yaml -n <your-namespace>
```

2. Create the Instrumentation configuration:

```bash
kubectl apply -f instrumentation.yaml -n <your-namespace>
```

3. Deploy your Java application with the instrumentation annotation:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-java-app
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-java: "java-instrumentation"
    spec:
      containers:
      - name: java-app
        image: my-java-app:latest
        resources:
          limits:
            memory: 1Gi
          requests:
            memory: 512Mi
```

4. Verify the deployment:

```bash
# Check if all pods are running
kubectl get pods

# Verify instrumentation injection
kubectl describe pod <your-app-pod> | grep -A 5 "Init Containers"

# Check application logs for OpenTelemetry agent
kubectl logs <your-app-pod> | grep otel
```

5. Sign in to [Last9](https://app.last9.io) and visit the APM dashboard to see the traces.

## How to Add OpenTelemetry to an Existing Java App in Kubernetes

To instrument your existing Java application with OpenTelemetry, follow these steps:

### 1. Deploy Required Infrastructure

Ensure the OpenTelemetry Operator and Collector are deployed in your cluster (see Installation section above).

### 2. Create Instrumentation Configuration

Apply the `instrumentation.yaml` configuration to your namespace:

```bash
kubectl apply -f instrumentation.yaml -n <your-namespace>
```

### 3. Add Annotation to Your Deployment

Add the following annotation to your deployment's pod template:

```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "java-instrumentation"
```

### 4. Update Resource Requirements

Ensure your container has adequate memory for the Java agent:

```yaml
resources:
  limits:
    memory: 1Gi      # Increase from your current limits
  requests:
    memory: 512Mi    # Minimum recommended
```

### 5. Configure Health Checks

Update health check paths if needed:

```yaml
readinessProbe:
  httpGet:
    path: /          # Or your actual health endpoint
    port: 8080
  initialDelaySeconds: 30
livenessProbe:
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 60
```

### 6. Deploy Your Application

Apply your updated deployment:

```bash
kubectl apply -f your-deployment.yaml
```

### 7. Verify Instrumentation

Check that the OpenTelemetry agent is loaded:

```bash
kubectl logs <your-app-pod> | grep "opentelemetry-javaagent"
```

Expected output: `opentelemetry-javaagent - version: X.X.X`

---

**Tip:** No code changes are required for basic instrumentation. The OpenTelemetry Java agent automatically instruments popular frameworks and libraries. For custom instrumentation, you can add manual spans using the OpenTelemetry API.

## Common Issues & Solutions

### Issue 1: Collector CrashLoopBackOff
**Cause**: Missing `check_interval` in memory_limiter processor  
**Solution**: Ensure `check_interval: 1s` is present in memory_limiter configuration

### Issue 2: Application Health Check Failures  
**Cause**: Wrong health check path or insufficient startup time  
**Solution**: Use correct health endpoint and increase `initialDelaySeconds`

### Issue 3: Connection Refused to Collector
**Cause**: Wrong service name in instrumentation  
**Solution**: Use `otel-collector:4318`

### Issue 4: No Traces in Last9
**Cause**: Authentication or endpoint configuration issues  
**Solution**: Verify Last9 credentials and check collector logs for export errors

---

*This guide is based on a successful implementation with K3s v1.32.6 and OpenTelemetry Operator v0.127.0*