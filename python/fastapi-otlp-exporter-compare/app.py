"""
FastAPI + OTel exporter compare: HTTP vs gRPC.

Context: OTLP HTTP exporter on long-lived `requests.Session` can hit
`RemoteDisconnected` when an upstream LB closes an idle keep-alive TCP
connection. gRPC exporter uses HTTP/2 with keepalive pings and avoids it.

Toggle with OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf | grpc
"""
import os
import logging
import uvicorn
from fastapi import FastAPI

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

PROTOCOL = os.getenv("OTEL_EXPORTER_OTLP_PROTOCOL", "http/protobuf").lower()
ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
HEADERS = os.getenv("OTEL_EXPORTER_OTLP_HEADERS", "")
SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "fastapi-otlp-compare")

if PROTOCOL == "grpc":
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    exporter = OTLPSpanExporter(endpoint=ENDPOINT or None)
else:
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    exporter = OTLPSpanExporter(endpoint=ENDPOINT or None)

provider = TracerProvider(resource=Resource.create({"service.name": SERVICE_NAME}))
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

logging.getLogger("opentelemetry.sdk._shared_internal").setLevel(logging.ERROR)

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
RequestsInstrumentor().instrument()

tracer = trace.get_tracer(__name__)


@app.get("/")
async def root():
    return {"protocol": PROTOCOL, "endpoint": ENDPOINT or "default"}


@app.get("/work")
async def work():
    with tracer.start_as_current_span("work"):
        return {"ok": True}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
