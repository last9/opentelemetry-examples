"""
Flask app simulating a publisher service.

Exposes a /publish endpoint that sends a message to SQS with trace context,
mimicking a real service-to-SQS-to-Lambda flow.
"""

import os
import logging

from flask import Flask, request, jsonify
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
from opentelemetry.baggage.propagation import W3CBaggagePropagator
from opentelemetry.instrumentation.flask import FlaskInstrumentor

from producer import send_message

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def init_tracing():
    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: os.environ.get(
            "OTEL_SERVICE_NAME", "publisher-service"
        ),
    })

    provider = TracerProvider(resource=resource)

    exporter = OTLPSpanExporter()  # Reads OTEL_EXPORTER_OTLP_* env vars
    provider.add_span_processor(BatchSpanProcessor(exporter))

    trace.set_tracer_provider(provider)

    # W3C TraceContext + Baggage propagators
    set_global_textmap(CompositePropagator([
        TraceContextTextMapPropagator(),
        W3CBaggagePropagator(),
    ]))

    return provider


provider = init_tracing()

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/publish", methods=["POST"])
def publish():
    """Send a message to SQS. The trace context is automatically propagated."""
    payload = request.get_json(force=True, silent=True) or {}
    payload.setdefault("source", "publisher-service")

    response = send_message(payload)
    return jsonify({
        "status": "sent",
        "messageId": response.get("MessageId"),
    })


if __name__ == "__main__":
    try:
        app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
    finally:
        provider.shutdown()
