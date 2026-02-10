"""
Production OpenTelemetry Configuration for OTLP
Replace the setup_otel() function in app.py with this for production
"""
import os
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

# OTLP Exporters for OTLP
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter


def setup_otel():
    """
    Setup OpenTelemetry with OTLP exporters for OTLP

    Environment Variables (Optional - defaults provided):
        SERVICE_NAME: Name of your service (default: sanic-service)
        K8S_POD_NAME: Pod name (auto-set in K8s)
        K8S_NAMESPACE: Namespace (auto-set in K8s)

    Environment Variables Required:
        OTLP_ENDPOINT: Your OTLP endpoint (e.g., https://your-endpoint:443)
        OTLP_AUTH_HEADER: Your authorization header (e.g., Basic <your-token>)

    Environment Variables Optional:
        SERVICE_NAME: Name of your service (default: sanic-service)
        K8S_POD_NAME: Pod name (auto-set in K8s)
        K8S_NAMESPACE: Namespace (auto-set in K8s)
    """

    # Read configuration from environment
    service_name = os.getenv("SERVICE_NAME", "sanic-service")

    # OTLP endpoint (required)
    otlp_endpoint = os.getenv("OTLP_ENDPOINT")
    if not otlp_endpoint:
        raise ValueError("OTLP_ENDPOINT environment variable is required")

    # Authentication header (required, gRPC metadata keys must be lowercase)
    otlp_auth_header = os.getenv("OTLP_AUTH_HEADER")
    if not otlp_auth_header:
        raise ValueError("OTLP_AUTH_HEADER environment variable is required")

    otlp_headers = {"authorization": otlp_auth_header}

    # Create resource with service and K8s metadata
    resource = Resource.create({
        "service.name": service_name,
        "service.version": os.getenv("SERVICE_VERSION", "1.0.0"),
        "deployment.environment": os.getenv("ENVIRONMENT", "production"),
        "k8s.pod.name": os.getenv("K8S_POD_NAME", os.getenv("HOSTNAME", "unknown")),
        "k8s.namespace.name": os.getenv("K8S_NAMESPACE", "default"),
        "k8s.deployment.name": os.getenv("K8S_DEPLOYMENT_NAME", service_name),
        "k8s.container.name": os.getenv("K8S_CONTAINER_NAME", "app"),
    })

    # Setup Tracing with OTLP exporter (exports to OTLP)
    trace_provider = TracerProvider(resource=resource)

    otlp_trace_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        headers=otlp_headers,
        insecure=False  # Use TLS
    )

    trace_provider.add_span_processor(
        BatchSpanProcessor(
            otlp_trace_exporter,
            max_queue_size=2048,
            max_export_batch_size=512,
            schedule_delay_millis=5000  # Export every 5 seconds
        )
    )

    trace.set_tracer_provider(trace_provider)

    # Setup Metrics with OTLP exporter (exports to OTLP)
    otlp_metric_exporter = OTLPMetricExporter(
        endpoint=otlp_endpoint,
        headers=otlp_headers,
        insecure=False  # Use TLS
    )

    metric_reader = PeriodicExportingMetricReader(
        exporter=otlp_metric_exporter,
        export_interval_millis=60000  # Export every 60 seconds
    )

    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader]
    )

    metrics.set_meter_provider(meter_provider)

    print(f"[OTEL] OpenTelemetry configured")
    print(f"[OTEL] Service: {service_name}")
    print(f"[OTEL] Endpoint: {otlp_endpoint}")
    print(f"[OTEL] Environment: {os.getenv('ENVIRONMENT', 'production')}")
    print(f"[OTEL] Exporting traces and metrics via OTLP")


# Example K8s Deployment YAML
"""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sanic-service
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sanic-service
  template:
    metadata:
      labels:
        app: sanic-service
    spec:
      containers:
      - name: app
        image: your-registry/sanic-service:latest
        ports:
        - containerPort: 8000
          name: http
        env:
        # Service name (optional, defaults to sanic-service)
        - name: SERVICE_NAME
          value: "order-service"

        # Environment (optional, defaults to production)
        - name: ENVIRONMENT
          value: "production"

        # K8s metadata (auto-injected by downward API)
        - name: K8S_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: K8S_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: K8S_DEPLOYMENT_NAME
          value: "sanic-service"
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name

        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"

        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 10

        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
"""
