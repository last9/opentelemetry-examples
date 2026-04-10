"""
Shared OpenTelemetry setup.

Reads standard OTEL_* environment variables — no extra config needed.
"""

import logging
import os

from opentelemetry import trace
from opentelemetry.baggage.propagation import W3CBaggagePropagator
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.kafka import KafkaInstrumentor
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

logger = logging.getLogger(__name__)


def init_tracing() -> TracerProvider:
    """Initialize the global tracer provider and auto-instrument kafka-python.

    Environment variables consumed:
        OTEL_SERVICE_NAME            — service.name resource attribute
        OTEL_EXPORTER_OTLP_ENDPOINT  — OTLP collector / Last9 endpoint
        OTEL_EXPORTER_OTLP_HEADERS   — e.g. "Authorization=Basic <token>"
        SERVICE_VERSION              — service.version resource attribute
        DEPLOYMENT_ENVIRONMENT       — deployment.environment resource attribute
    """
    resource = Resource.create({
        "service.name": os.environ.get("OTEL_SERVICE_NAME", "kafka-python-consumer"),
        "service.version": os.environ.get("SERVICE_VERSION", "1.0.0"),
        "deployment.environment": os.environ.get("DEPLOYMENT_ENVIRONMENT", "development"),
    })

    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)

    set_global_textmap(CompositePropagator([
        TraceContextTextMapPropagator(),
        W3CBaggagePropagator(),
    ]))

    # One call auto-instruments all KafkaProducer and KafkaConsumer instances.
    # It injects/extracts W3C traceparent headers and creates PRODUCER/CONSUMER
    # spans automatically — no manual inject/extract needed in application code.
    KafkaInstrumentor().instrument()

    logger.info(
        "Tracing initialised — service=%s endpoint=%s",
        os.environ.get("OTEL_SERVICE_NAME", "kafka-python-consumer"),
        os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "https://otlp.last9.io"),
    )
    return provider


def shutdown_tracing(provider: TracerProvider) -> None:
    """Flush pending spans and shut down gracefully."""
    logger.info("Flushing spans before shutdown…")
    provider.force_flush(timeout_millis=5000)
    provider.shutdown()
