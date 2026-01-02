"""
Cloud Run Flask Application with OpenTelemetry
Sends traces, logs, and metrics to Last9

This example demonstrates:
- Direct OTLP export to Last9
- Structured JSON logging with trace correlation
- Cloud Run resource detection
- Graceful shutdown for span flushing
"""
import os
import sys
import json
import atexit
import logging
import signal
from datetime import datetime

from flask import Flask, jsonify, request
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.semconv.resource import ResourceAttributes


def get_cloud_run_resource():
    """Create resource with Cloud Run-specific attributes."""
    service_name = os.environ.get("OTEL_SERVICE_NAME", "flask-cloud-run")

    return Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_VERSION: os.environ.get("SERVICE_VERSION", "1.0.0"),
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: os.environ.get("DEPLOYMENT_ENVIRONMENT", "production"),
        # Cloud Run specific attributes
        "cloud.provider": "gcp",
        "cloud.platform": "gcp_cloud_run_revision",
        "cloud.region": os.environ.get("CLOUD_RUN_REGION", os.environ.get("GOOGLE_CLOUD_REGION", "unknown")),
        "cloud.account.id": os.environ.get("GOOGLE_CLOUD_PROJECT", "unknown"),
        # FaaS attributes (Cloud Run is serverless)
        "faas.name": os.environ.get("K_SERVICE", service_name),
        "faas.version": os.environ.get("K_REVISION", "unknown"),
        "faas.instance": os.environ.get("K_REVISION", "unknown"),
        # Service instance
        "service.instance.id": os.environ.get("K_REVISION", "local"),
    })


def parse_otlp_headers():
    """Parse OTLP headers from environment variable."""
    headers_str = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    headers = {}

    if headers_str:
        for pair in headers_str.split(","):
            if "=" in pair:
                key, value = pair.split("=", 1)
                headers[key.strip()] = value.strip()

    return headers


def initialize_telemetry():
    """Initialize OpenTelemetry tracing and metrics."""
    resource = get_cloud_run_resource()
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "https://your-otlp-endpoint")
    headers = parse_otlp_headers()

    # Initialize Tracing
    trace_exporter = OTLPSpanExporter(
        endpoint=f"{endpoint}/v1/traces",
        headers=headers,
    )

    trace_provider = TracerProvider(resource=resource)
    # Use BatchSpanProcessor for efficiency, with reasonable timeout for cold starts
    trace_provider.add_span_processor(
        BatchSpanProcessor(
            trace_exporter,
            max_export_batch_size=512,
            schedule_delay_millis=5000,  # 5 second delay
        )
    )
    trace.set_tracer_provider(trace_provider)

    # Initialize Metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=f"{endpoint}/v1/metrics",
        headers=headers,
    )

    metric_reader = PeriodicExportingMetricReader(
        metric_exporter,
        export_interval_millis=60000,  # Export every 60 seconds
    )

    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader],
    )
    metrics.set_meter_provider(meter_provider)

    return trace_provider, meter_provider


# Initialize telemetry before creating the app
trace_provider, meter_provider = initialize_telemetry()
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# Create custom metrics
request_counter = meter.create_counter(
    name="http_requests_total",
    description="Total number of HTTP requests",
    unit="1",
)

request_duration = meter.create_histogram(
    name="http_request_duration_seconds",
    description="HTTP request duration in seconds",
    unit="s",
)


class CloudRunJsonFormatter(logging.Formatter):
    """JSON formatter with Cloud Logging trace correlation."""

    def format(self, record):
        # Get current span for trace correlation
        span = trace.get_current_span()
        span_context = span.get_span_context() if span else None

        log_entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "logger": record.name,
        }

        # Add trace correlation for Cloud Logging
        if span_context and span_context.is_valid:
            project_id = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
            if project_id:
                log_entry["logging.googleapis.com/trace"] = \
                    f"projects/{project_id}/traces/{format(span_context.trace_id, '032x')}"
                log_entry["logging.googleapis.com/spanId"] = format(span_context.span_id, '016x')
                log_entry["logging.googleapis.com/trace_sampled"] = span_context.trace_flags.sampled

        # Add exception info if present
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_entry)


# Configure structured logging
def setup_logging():
    """Configure logging with JSON output for Cloud Logging."""
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)

    # Remove default handlers
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)

    # Add JSON handler for stdout
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(CloudRunJsonFormatter())
    root_logger.addHandler(handler)

    return logging.getLogger(__name__)


logger = setup_logging()

# Create Flask app
app = Flask(__name__)

# Instrument Flask and requests library
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()


@app.before_request
def before_request():
    """Record request start time for duration metric."""
    request.start_time = datetime.utcnow()


@app.after_request
def after_request(response):
    """Record request metrics."""
    # Record request count
    request_counter.add(
        1,
        attributes={
            "http.method": request.method,
            "http.route": request.path,
            "http.status_code": response.status_code,
        }
    )

    # Record request duration
    if hasattr(request, 'start_time'):
        duration = (datetime.utcnow() - request.start_time).total_seconds()
        request_duration.record(
            duration,
            attributes={
                "http.method": request.method,
                "http.route": request.path,
            }
        )

    return response


@app.route("/")
def home():
    """Home endpoint."""
    logger.info("Home endpoint accessed")
    return jsonify({
        "message": "Hello from Cloud Run with OpenTelemetry!",
        "service": os.environ.get("K_SERVICE", "local"),
        "revision": os.environ.get("K_REVISION", "local"),
    })


@app.route("/users", methods=["GET"])
def get_users():
    """Example endpoint with custom span."""
    with tracer.start_as_current_span("fetch_users_from_database") as span:
        # Simulate database query
        users = [
            {"id": 1, "name": "Alice", "email": "alice@example.com"},
            {"id": 2, "name": "Bob", "email": "bob@example.com"},
            {"id": 3, "name": "Charlie", "email": "charlie@example.com"},
        ]

        span.set_attribute("db.system", "postgresql")
        span.set_attribute("db.operation", "SELECT")
        span.set_attribute("user.count", len(users))
        span.add_event("Users fetched successfully")

        logger.info(f"Returning {len(users)} users")
        return jsonify(users)


@app.route("/users/<int:user_id>", methods=["GET"])
def get_user(user_id):
    """Get a specific user with custom span attributes."""
    with tracer.start_as_current_span("fetch_user_by_id") as span:
        span.set_attribute("user.id", user_id)

        # Simulate user lookup
        if user_id <= 0:
            span.set_attribute("error", True)
            logger.warning(f"Invalid user ID requested: {user_id}")
            return jsonify({"error": "Invalid user ID"}), 400

        user = {"id": user_id, "name": f"User {user_id}", "email": f"user{user_id}@example.com"}
        logger.info(f"Retrieved user {user_id}")
        return jsonify(user)


@app.route("/error")
def error_endpoint():
    """Endpoint that demonstrates error handling."""
    with tracer.start_as_current_span("error_operation") as span:
        try:
            # Simulate an error
            raise ValueError("This is a simulated error for testing")
        except Exception as e:
            span.set_attribute("error", True)
            span.record_exception(e)
            logger.error(f"Error occurred: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500


@app.route("/health")
def health():
    """Health check endpoint (not instrumented with custom spans)."""
    return jsonify({"status": "healthy"})


@app.route("/ready")
def ready():
    """Readiness check endpoint."""
    return jsonify({"status": "ready"})


def shutdown_telemetry():
    """Gracefully shutdown telemetry providers."""
    logger.info("Shutting down telemetry...")
    try:
        trace_provider.force_flush(timeout_millis=5000)
        trace_provider.shutdown()
        meter_provider.force_flush(timeout_millis=5000)
        meter_provider.shutdown()
        logger.info("Telemetry shutdown complete")
    except Exception as e:
        print(f"Error during telemetry shutdown: {e}", file=sys.stderr)


def handle_sigterm(signum, frame):
    """Handle SIGTERM for graceful shutdown."""
    logger.info("Received SIGTERM, initiating graceful shutdown")
    shutdown_telemetry()
    sys.exit(0)


# Register shutdown handlers
atexit.register(shutdown_telemetry)
signal.signal(signal.SIGTERM, handle_sigterm)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    logger.info(f"Starting Flask app on port {port}")
    app.run(host="0.0.0.0", port=port, debug=False)
