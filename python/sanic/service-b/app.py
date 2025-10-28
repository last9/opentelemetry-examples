from sanic import Sanic, response
from opentelemetry import trace, context
from opentelemetry.propagate import extract
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import ParentBased, ALWAYS_ON, ALWAYS_OFF, TraceIdRatioBased
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.trace import SpanKind, Status, StatusCode
import os

app = Sanic("service-b")


def _parse_resource_attributes():
    """Parse OTEL_RESOURCE_ATTRIBUTES environment variable"""
    resource_attrs = os.getenv("OTEL_RESOURCE_ATTRIBUTES", "")
    attrs = {}

    if resource_attrs:
        for attr in resource_attrs.split(","):
            if "=" in attr:
                key, value = attr.split("=", 1)
                attrs[key.strip()] = value.strip()

    return attrs


def _get_sampler():
    """Get sampler based on OTEL_TRACES_SAMPLER environment variable"""
    sampler_name = os.getenv("OTEL_TRACES_SAMPLER", "always_on")

    if sampler_name == "always_on":
        return ParentBased(root=ALWAYS_ON)
    elif sampler_name == "always_off":
        return ParentBased(root=ALWAYS_OFF)
    elif sampler_name == "traceidratio":
        ratio = float(os.getenv("OTEL_TRACES_SAMPLER_ARG", "0.1"))
        return ParentBased(root=TraceIdRatioBased(ratio))
    else:
        return ParentBased(root=ALWAYS_ON)


# Initialize OpenTelemetry in the worker process
@app.before_server_start
async def setup_opentelemetry(app, loop):
    """Initialize OpenTelemetry when worker starts"""
    # Get configuration from environment variables
    service_name = os.getenv("OTEL_SERVICE_NAME", "service-b")
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    auth_header = os.getenv("OTEL_EXPORTER_OTLP_HEADERS")

    # Parse resource attributes
    resource_attrs = _parse_resource_attributes()
    resource_attrs[SERVICE_NAME] = service_name

    # Create resource with service information
    resource = Resource(attributes=resource_attrs)

    # Get sampler
    sampler = _get_sampler()

    # Setup tracer provider with sampler
    provider = TracerProvider(resource=resource, sampler=sampler)

    # Parse authorization header (gRPC requires lowercase keys)
    headers = {}
    if auth_header:
        for header in auth_header.split(","):
            if "=" in header:
                key, value = header.split("=", 1)
                headers[key.strip().lower()] = value.strip()

    # Configure OTLP exporter
    exporter = OTLPSpanExporter(
        endpoint=endpoint,
        headers=headers,
    )

    # Use BatchSpanProcessor for better performance
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # Auto-instrument HTTP clients
    from opentelemetry.instrumentation.aiohttp_client import AioHttpClientInstrumentor
    AioHttpClientInstrumentor().instrument()

# Get tracer for creating spans
tracer = trace.get_tracer(__name__)


# OpenTelemetry middleware to create root spans for incoming requests
@app.middleware("request")
async def otel_request_middleware(request):
    """Extract trace context and create root span for incoming request"""
    # Extract context from incoming headers (for distributed tracing)
    ctx = extract(request.headers)

    # Create root span for this request with SERVER span kind
    span = tracer.start_span(
        f"{request.method} {request.path}",
        context=ctx,
        kind=SpanKind.SERVER
    )

    # Set span attributes
    span.set_attribute("http.method", request.method)
    span.set_attribute("http.url", str(request.url))
    span.set_attribute("http.target", request.path)
    span.set_attribute("http.scheme", request.scheme)

    # Attach context and make span current
    token = context.attach(ctx)
    ctx_with_span = trace.set_span_in_context(span, ctx)
    token_span = context.attach(ctx_with_span)

    # Store for cleanup in response middleware
    request.ctx.otel_span = span
    request.ctx.otel_token = token
    request.ctx.otel_token_span = token_span


@app.middleware("response")
async def otel_response_middleware(request, response):
    """End span and cleanup context"""
    if not hasattr(request.ctx, 'otel_span'):
        return

    span = request.ctx.otel_span

    if response:
        span.set_attribute("http.status_code", response.status)
        if response.status >= 400:
            span.set_status(Status(StatusCode.ERROR))

    span.end()

    # Cleanup context
    if hasattr(request.ctx, 'otel_token_span'):
        context.detach(request.ctx.otel_token_span)
    if hasattr(request.ctx, 'otel_token'):
        context.detach(request.ctx.otel_token)


@app.exception(Exception)
async def handle_exception(request, exception):
    """Capture exceptions in OpenTelemetry spans"""
    if hasattr(request.ctx, 'otel_span'):
        span = request.ctx.otel_span

        # Record the exception with full stack trace
        span.record_exception(exception)

        # Set span status to error
        span.set_status(Status(StatusCode.ERROR, str(exception)))

        # Add exception details as attributes
        span.set_attribute("exception.type", type(exception).__name__)
        span.set_attribute("exception.message", str(exception))

    # Re-raise to let Sanic handle it normally
    raise exception


@app.route("/health")
async def health(request):
    return response.json({"service": "service-b", "status": "healthy"})


@app.route("/process")
async def process(request):
    return response.json({
        "service": "service-b",
        "message": "Processing complete",
        "data": "Some processed data from service-b"
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8002, debug=True)
