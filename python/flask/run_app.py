from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    BatchSpanProcessor,
)
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

from app import app


resource = Resource(attributes={
    ResourceAttributes.SERVICE_NAME: "flask-api-service", # replace with env variable or acutal service name
    ResourceAttributes.DEPLOYMENT_ENVIRONMENT: "dev", # replace with env variable
})

provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(OTLPSpanExporter())

provider.add_span_processor(processor)
# Sets the global default tracer provider
trace.set_tracer_provider(provider)

instrumentor = FlaskInstrumentor()

instrumentor.instrument_app(app)

app.run(port=5000)
