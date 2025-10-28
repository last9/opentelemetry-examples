# OpenTelemetry Integration for Sanic

Use OpenTelemetry to instrument your Sanic application and send telemetry data to Last9. This guide shows you how to send telemetry directly from your application to Last9's OTLP endpoint.

---

## Instrumentation packages

Install the following packages:

```sh
pip install \
  sanic>=21.0 \
  opentelemetry-api==1.27.0 \
  opentelemetry-sdk==1.27.0 \
  opentelemetry-exporter-otlp-proto-grpc==1.27.0 \
  opentelemetry-instrumentation-aiohttp-client==0.48b0
```

**For database instrumentation (install what you use):**

```sh
# Async PostgreSQL
pip install opentelemetry-instrumentation-asyncpg==0.48b0

# PostgreSQL
pip install opentelemetry-instrumentation-psycopg2==0.48b0

# Redis
pip install opentelemetry-instrumentation-redis==0.48b0

# SQLAlchemy
pip install opentelemetry-instrumentation-sqlalchemy==0.48b0
```

---

## Setup auto-instrumentation using OpenTelemetry

### Environment variables

Set the environment variables:

```sh
export OTEL_SERVICE_NAME="<your_service_name>"
export OTEL_EXPORTER_OTLP_ENDPOINT="<Last9_OTLP_Endpoint>"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=<Last9_Auth_Token>"
export OTEL_TRACES_SAMPLER="always_on"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
export OTEL_LOG_LEVEL="error"
export OTEL_METRICS_EXPORTER="none"
export OTEL_LOGS_EXPORTER="none"
```
---

### Python

Create a file named `instrumentation.py` and add the following code:

```python
"""OpenTelemetry instrumentation for Sanic application"""
import os
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import (
    TraceIdRatioBased,
    ParentBased,
    ALWAYS_ON,
    ALWAYS_OFF
)
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME

# Simple logging utility
logger = logging.getLogger(__name__)


def _setup_logging():
    """Configure logging based on OTEL_LOG_LEVEL"""
    log_level = os.getenv("OTEL_LOG_LEVEL", "error").upper()
    level_map = {
        "DEBUG": logging.DEBUG,
        "INFO": logging.INFO,
        "WARNING": logging.WARNING,
        "ERROR": logging.ERROR,
    }
    logging.basicConfig(
        level=level_map.get(log_level, logging.ERROR),
        format='[%(name)s] %(message)s'
    )


def _get_sampler():
    """Get sampler based on OTEL_TRACES_SAMPLER environment variable"""
    sampler_name = os.getenv("OTEL_TRACES_SAMPLER", "always_on")

    if sampler_name == "always_on":
        return ParentBased(root=ALWAYS_ON)
    elif sampler_name == "always_off":
        return ParentBased(root=ALWAYS_OFF)
    elif sampler_name == "traceidratio":
        # Get ratio from OTEL_TRACES_SAMPLER_ARG, default to 0.1 (10%)
        ratio = float(os.getenv("OTEL_TRACES_SAMPLER_ARG", "0.1"))
        return ParentBased(root=TraceIdRatioBased(ratio))
    else:
        return ParentBased(root=ALWAYS_ON)


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


def init_telemetry():
    """
    Initialize OpenTelemetry tracing.
    Must be called in each worker process for Sanic.
    """
    # Setup logging
    _setup_logging()

    # Get configuration from environment variables
    service_name = os.getenv("OTEL_SERVICE_NAME", "my-sanic-app")
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    auth_header = os.getenv("OTEL_EXPORTER_OTLP_HEADERS")

    logger.info(f"Initializing OpenTelemetry for service: {service_name}")

    # Parse resource attributes
    resource_attrs = _parse_resource_attributes()
    resource_attrs[SERVICE_NAME] = service_name

    # Create resource with service information
    resource = Resource(attributes=resource_attrs)

    # Get sampler
    sampler = _get_sampler()

    # Setup tracer provider with sampler
    provider = TracerProvider(
        resource=resource,
        sampler=sampler
    )

    # Parse authorization header
    headers = {}
    if auth_header:
        for header in auth_header.split(","):
            if "=" in header:
                key, value = header.split("=", 1)
                headers[key.strip()] = value.strip()

    # Configure OTLP exporter for Last9
    exporter = OTLPSpanExporter(
        endpoint=endpoint,
        headers=headers,
    )

    # Use BatchSpanProcessor for better performance
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # Auto-instrument libraries
    _instrument_libraries()

    logger.info("Tracing initialized successfully")


def _instrument_libraries():
    """Automatically instrument HTTP clients and databases"""
    # HTTP clients
    try:
        from opentelemetry.instrumentation.aiohttp_client import AioHttpClientInstrumentor
        AioHttpClientInstrumentor().instrument()
    except ImportError:
        pass

    # Databases - add instrumentation for what you use
    try:
        from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor
        AsyncPGInstrumentor().instrument()
    except ImportError:
        pass

    try:
        from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
        Psycopg2Instrumentor().instrument()
    except ImportError:
        pass

    try:
        from opentelemetry.instrumentation.redis import RedisInstrumentor
        RedisInstrumentor().instrument()
    except ImportError:
        pass

    try:
        from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
        SQLAlchemyInstrumentor().instrument()
    except ImportError:
        pass
```

---

### Create Sanic middleware

Create a file named `otel_middleware.py`:

```python
"""OpenTelemetry middleware for Sanic"""
from opentelemetry import trace, context
from opentelemetry.propagate import extract
from opentelemetry.trace import SpanKind, Status, StatusCode


def get_tracer():
    return trace.get_tracer(__name__)


async def otel_request_middleware(request):
    """Create SERVER span for incoming request"""
    tracer = get_tracer()

    # Extract trace context from incoming headers for distributed tracing
    ctx = extract(request.headers)

    # Create SERVER span
    span = tracer.start_span(
        f"{request.method} {request.path}",
        context=ctx,
        kind=SpanKind.SERVER
    )

    # Set HTTP semantic convention attributes
    span.set_attribute("http.method", request.method)
    span.set_attribute("http.url", str(request.url))
    span.set_attribute("http.target", request.path)
    span.set_attribute("http.scheme", request.scheme)

    # Attach context
    token = context.attach(ctx)
    ctx_with_span = trace.set_span_in_context(span, ctx)
    token_span = context.attach(ctx_with_span)

    # Store for cleanup
    request.ctx.otel_span = span
    request.ctx.otel_token = token
    request.ctx.otel_token_span = token_span


async def otel_response_middleware(request, response):
    """Finalize span after response"""
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
```

---

### Add exception handler for error tracking

Create a file named `exception_handler.py` to capture exceptions with full stack traces:

```python
"""Exception handler for OpenTelemetry"""
from opentelemetry.trace import Status, StatusCode


async def otel_exception_handler(request, exception):
    """Capture exceptions in OpenTelemetry spans with full stack traces"""
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
```

**Why this is needed:**

The response middleware only captures HTTP status codes (like 500). To capture actual exception details, stack traces, and error messages in Last9, you need to add an exception handler. This handler will:

- Record the full exception stack trace in the span
- Mark the span as ERROR status
- Add exception type and message as span attributes
- Allow you to see detailed error information in Last9's APM

---

### Integrate with your Sanic application

Import the instrumentation at the top of your application's entry point file (e.g., `app.py` or `server.py`):

```python
from sanic import Sanic, response
from instrumentation import init_telemetry
from otel_middleware import otel_request_middleware, otel_response_middleware
from exception_handler import otel_exception_handler

app = Sanic("my-app")


# IMPORTANT: Initialize OpenTelemetry in worker process
@app.before_server_start
async def setup_telemetry(app, loop):
    """Initialize OpenTelemetry when Sanic worker starts"""
    init_telemetry()


# Register OpenTelemetry middleware
app.middleware("request")(otel_request_middleware)
app.middleware("response")(otel_response_middleware)

# Register exception handler for error tracking
app.exception(Exception)(otel_exception_handler)


# Your application routes
@app.route("/")
async def index(request):
    return response.json({"message": "Hello World"})


@app.route("/health")
async def health(request):
    return response.json({"status": "healthy"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
```

---

## What the code does

The above code performs the following steps:

1. **Set up Trace Provider** with the application's name as Service Name
2. **Set up OTLP Exporter** with Last9 OTLP endpoint and authentication
3. **Set up auto-instrumentation** for HTTP clients (aiohttp) and databases
4. **Create Sanic middleware** to generate SERVER spans for incoming HTTP requests
5. **Extract and propagate trace context** for distributed tracing across services

Once you run the Sanic application, it will start sending telemetry data to Last9.

---

## Database integration example

If you're using databases, they're automatically instrumented. Just ensure you create database connections **after** calling `init_telemetry()`:

### Async PostgreSQL (asyncpg)

```python
import asyncpg

@app.before_server_start
async def setup(app, loop):
    # 1. Initialize OpenTelemetry FIRST
    init_telemetry()

    # 2. Create database pool (automatically instrumented)
    app.ctx.db = await asyncpg.create_pool(
        host="localhost",
        database="mydb",
        user="user",
        password="password"
    )

@app.route("/users/<user_id:int>")
async def get_user(request, user_id):
    async with request.app.ctx.db.acquire() as conn:
        # Database queries are automatically traced
        user = await conn.fetchrow("SELECT * FROM users WHERE id = $1", user_id)
        return response.json(dict(user))
```

### Redis

```python
import aioredis

@app.before_server_start
async def setup(app, loop):
    init_telemetry()
    app.ctx.redis = await aioredis.create_redis_pool("redis://localhost")

@app.route("/cache/<key>")
async def get_cache(request, key):
    # Redis operations are automatically traced
    value = await request.app.ctx.redis.get(key)
    return response.json({"value": value})
```

---

## Run your application

Set all environment variables and run:

```sh
export OTEL_SERVICE_NAME="my-sanic-app"
export OTEL_EXPORTER_OTLP_ENDPOINT="<Last9_OTLP_Endpoint>"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=<Last9_Auth_Token>"
export OTEL_TRACES_SAMPLER="always_on"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
export OTEL_LOG_LEVEL="error"
export OTEL_METRICS_EXPORTER="none"
export OTEL_LOGS_EXPORTER="none"

python app.py
```

**For development with debug logging:**

```sh
export OTEL_LOG_LEVEL="debug"
python app.py
```

**For production with sampling (10% of traces):**

```sh
export OTEL_TRACES_SAMPLER="traceidratio"
export OTEL_TRACES_SAMPLER_ARG="0.1"
python app.py
```

---

## View traces in Last9

1. Go to **Last9 Dashboard → APM → Traces**
2. Filter by service name: `my-sanic-app`
3. You should see traces with:
   - **SERVER spans**: Incoming HTTP requests
   - **CLIENT spans**: Outgoing HTTP calls (automatically traced)
   - **DATABASE spans**: SQL queries (if database instrumentation is installed)

---
