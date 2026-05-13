"""OTel SDK init for pip-only path (no ADOT layer, no Lambda extension).

Activates monkey-patch instrumentation via Instrumentor().instrument() calls.
Reads endpoint + auth from env (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_HEADERS).
"""
import os


def init_otel(service_name: str) -> None:
    # Skip locally (chalice local, pytest, dev shell). Lambda runtime sets this.
    if not os.environ.get("AWS_LAMBDA_FUNCTION_NAME") and not os.environ.get("OTEL_FORCE_INIT"):
        return

    from opentelemetry import trace
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    # NOTE: AwsLambdaInstrumentor is intentionally NOT used here.
    # Chalice's Lambda handler is the Chalice `app` object (a class instance, not a
    # function), and AwsLambdaInstrumentor uses wrapt to wrap a function — it crashes
    # trying to wrap `app.app`. Chalice manages its own request lifecycle; the rest
    # of the instrumentors below cover outbound calls and AWS SDK use.
    from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
    from opentelemetry.instrumentation.requests import RequestsInstrumentor
    from opentelemetry.instrumentation.urllib3 import URLLib3Instrumentor
    from opentelemetry.instrumentation.logging import LoggingInstrumentor
    from opentelemetry.instrumentation.aiohttp_client import AioHttpClientInstrumentor

    resource = Resource.create({
        "service.name": service_name,
        "service.namespace": os.environ.get("OTEL_SERVICE_NAMESPACE", "chalice-adot"),
        "deployment.environment": os.environ.get("OTEL_DEPLOYMENT_ENV", "dev"),
    })
    provider = TracerProvider(resource=resource)
    # SimpleSpanProcessor: synchronous flush per span — safer under Lambda freeze/thaw.
    # Switch to BatchSpanProcessor + force_flush in handler if throughput hurts.
    provider.add_span_processor(SimpleSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)

    BotocoreInstrumentor().instrument()
    RequestsInstrumentor().instrument()
    URLLib3Instrumentor().instrument()
    LoggingInstrumentor().instrument()
    AioHttpClientInstrumentor().instrument()
