from sanic import Sanic, response
import aiohttp
from opentelemetry import trace, context
from opentelemetry.propagate import extract
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import ParentBased, ALWAYS_ON, ALWAYS_OFF, TraceIdRatioBased
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.trace import SpanKind, Status, StatusCode
import os

app = Sanic("service-a")


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
    service_name = os.getenv("OTEL_SERVICE_NAME", "service-a")
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

SERVICE_B_URL = "http://localhost:8002"
SERVICE_A_URL = "http://localhost:8001"


@app.route("/health")
async def health(request):
    return response.json({"service": "service-a", "status": "healthy"})


@app.route("/error")
async def error_test(request):
    """Test endpoint that throws an exception"""
    raise ValueError("This is a test error to demonstrate exception tracking")


@app.route("/internal")
async def internal(request):
    """Internal endpoint that service-a calls itself"""
    return response.json({
        "service": "service-a",
        "message": "Internal processing complete"
    })


@app.route("/call-service-b")
async def call_service_b(request):
    """Calls service-b and returns the response"""
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{SERVICE_B_URL}/process") as resp:
            data = await resp.json()
            return response.json({
                "service": "service-a",
                "called": "service-b",
                "response_from_service_b": data
            })


@app.route("/call-self")
async def call_self(request):
    """Calls its own internal endpoint"""
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{SERVICE_A_URL}/internal") as resp:
            data = await resp.json()
            return response.json({
                "service": "service-a",
                "called": "service-a (self)",
                "response_from_internal": data
            })


@app.route("/call-chain")
async def call_chain(request):
    """Calls service-b and then calls itself - demonstrates full chain"""
    async with aiohttp.ClientSession() as session:
        # First call service-b
        async with session.get(f"{SERVICE_B_URL}/process") as resp:
            service_b_data = await resp.json()

        # Then call self
        async with session.get(f"{SERVICE_A_URL}/internal") as resp:
            self_data = await resp.json()

        return response.json({
            "service": "service-a",
            "chain": ["service-a", "service-b", "service-a"],
            "service_b_response": service_b_data,
            "self_response": self_data
        })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8001, debug=True)
