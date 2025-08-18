import os
import platform
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource

# Fix for macOS proxy-related crashes
if platform.system() == "Darwin":
    os.environ["NO_PROXY"] = "*"

# Server socket
bind = "0.0.0.0:8005"
backlog = 2048

# Worker processes (set to 1 on macOS to avoid fork issues)
workers = 1
worker_class = "uvicorn.workers.UvicornWorker"
worker_connections = 1000
timeout = 60
keepalive = 2

# Restart workers after this many requests, to prevent memory leaks
max_requests = 5000
max_requests_jitter = 1000

# Logging
loglevel = "info"
errorlog = "-"
accesslog = "-"

# Process naming
proc_name = "fastapi-otel-app"

# Server mechanics
daemon = False
pidfile = "/tmp/gunicorn.pid"
user = None
group = None
tmp_upload_dir = None

# Pre-load app for better performance (required on macOS to avoid fork issues)
preload_app = True

def post_fork(server, worker):
    """Initialize OpenTelemetry tracing in each worker process after forking."""
    server.log.info("Worker spawned (pid: %s)", worker.pid)

    # Try to create resource with your specified detectors, fall back to manual resource if it fails
    try:
        # Set environment variables for resource detection
        os.environ.setdefault("OTEL_EXPERIMENTAL_RESOURCE_DETECTORS", "process,aws_ec2,aws_ecs,containerid")
        
        # Let OpenTelemetry auto-detect resources
        resource = Resource.create()
        server.log.info("Successfully created resource with auto-detection")
        
    except (StopIteration, Exception) as e:
        # Fallback to manual resource creation if auto-detection fails
        server.log.warning("Resource auto-detection failed (%s), using manual resource creation", e)
        resource = Resource.create({
            "service.name": os.environ.get("OTEL_SERVICE_NAME", "your-app-name"),
            "service.version": os.environ.get("OTEL_SERVICE_VERSION", "1.0.0"),
        })

    # Initialize tracing with the resource (auto-detected or manual)
    tracer_provider = TracerProvider(resource=resource)
    trace.set_tracer_provider(tracer_provider)

    # Configure span exporter
    try:
        span_exporter = OTLPSpanExporter()
        trace.get_tracer_provider().add_span_processor(
            BatchSpanProcessor(span_exporter)
        )
        server.log.info("OpenTelemetry tracing initialized for worker %s", worker.pid)
        
    except Exception as e:
        server.log.error("Failed to initialize OTLP exporter for worker %s: %s", worker.pid, e)

def worker_exit(server, worker):
    """Clean up when worker exits."""
    server.log.info("Worker exited (pid: %s)", worker.pid)

