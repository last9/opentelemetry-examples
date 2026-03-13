import json
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

# Helper function to get trace context for print statements
def get_trace_context():
    """Get current trace_id and span_id for logging"""
    span = trace.get_current_span()
    if span:
        span_context = span.get_span_context()
        if span_context.is_valid:
            return {
                'trace_id': format(span_context.trace_id, '032x'),
                'span_id': format(span_context.span_id, '016x')
            }
    return {
        'trace_id': '0' * 32,
        'span_id': '0' * 16
    }

# Helper function to print with trace context
def print_with_trace(message, level="INFO"):
    """Print message with trace context"""
    ctx = get_trace_context()
    print(f"[{level}] [trace_id={ctx['trace_id']} span_id={ctx['span_id']}] {message}")

_tracer_initialized = False
_span_processor = None

def init_tracer():
    """Initialize OpenTelemetry tracer with OTLP exporter"""
    global _tracer_initialized, _span_processor
    if _tracer_initialized:
        return

    # Create resource with service name and parse deployment.environment from OTEL_RESOURCE_ATTRIBUTES
    resource_attrs = {
        "service.name": os.environ.get("OTEL_SERVICE_NAME", "lambda-service"),
    }

    # Parse OTEL_RESOURCE_ATTRIBUTES if provided (format: key1=value1,key2=value2)
    otel_resource_attrs = os.environ.get("OTEL_RESOURCE_ATTRIBUTES", "")
    if otel_resource_attrs:
        for pair in otel_resource_attrs.split(","):
            if "=" in pair:
                key, value = pair.split("=", 1)
                resource_attrs[key.strip()] = value.strip()

    resource = Resource.create(resource_attrs)

    # Create tracer provider
    provider = TracerProvider(resource=resource)

    # Configure OTLP exporter
    otlp_exporter = OTLPSpanExporter(
        endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT") + "/v1/traces",
        headers={
            "authorization": os.environ.get("OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION", "")
        }
    )

    # Add span processor and keep reference for flushing
    _span_processor = BatchSpanProcessor(otlp_exporter)
    provider.add_span_processor(_span_processor)

    # Set as global tracer provider
    trace.set_tracer_provider(provider)

    _tracer_initialized = True
    print_with_trace("OpenTelemetry tracer initialized manually with OTLP exporter")

def lambda_handler(event, context):
    global _span_processor

    # Initialize tracer first
    init_tracer()

    # Get tracer after initialization
    tracer = trace.get_tracer(__name__)

    # Create an explicit span for this Lambda invocation
    with tracer.start_as_current_span("lambda_handler") as span:
        span.set_attribute("faas.execution", context.aws_request_id)
        span.set_attribute("faas.name", context.function_name)

        print_with_trace("Lambda invocation started")
        print_with_trace(f"Request ID: {context.aws_request_id}")
        print_with_trace(f"Processing test event: {json.dumps(event)}")

        # Simulate some work with child spans
        with tracer.start_as_current_span("validate_input") as validate_span:
            print_with_trace("Step 1: Validating input")
            validate_span.set_attribute("validation.result", "success")

        with tracer.start_as_current_span("process_data") as process_span:
            print_with_trace("Step 2: Processing data")
            process_span.set_attribute("processing.items", 1)

        with tracer.start_as_current_span("prepare_response") as response_span:
            print_with_trace("Step 3: Preparing response")
            response_span.set_attribute("response.status", "success")

        result = {
            "statusCode": 200,
            "body": {
                "status": "success",
                "message": "Manual OTLP trace export test with trace_id in logs",
                "trace_id": format(span.get_span_context().trace_id, '032x'),
                "span_id": format(span.get_span_context().span_id, '016x')
            }
        }

        print_with_trace("Processing completed successfully")
        print_with_trace("This is a test warning - should have trace context", level="WARNING")

    # Force flush spans before Lambda terminates
    if _span_processor:
        print_with_trace("Forcing span processor flush...")
        _span_processor.force_flush(timeout_millis=5000)
        print_with_trace("Span processor flush completed")

    return result
