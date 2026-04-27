"""
FastAPI app wired up with the custom sampler.
Use this when you need more control than OTEL_PYTHON_EXCLUDED_URLS offers.
"""

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

from sampler import sampler

# Configure TracerProvider with the custom sampler before any instrumentation
provider = TracerProvider(sampler=sampler)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)

from fastapi import FastAPI
import uvicorn
import time
import random

app = FastAPI(title="Trace Filtering Demo (custom sampler)")
FastAPIInstrumentor.instrument_app(app)


@app.get("/health-check")
async def health_check():
    return {"status": "ok"}


@app.get("/")
async def root():
    return {"message": "Trace filtering demo running"}


@app.get("/api/orders")
async def list_orders():
    time.sleep(random.uniform(0.01, 0.05))
    return {"orders": [{"id": "ord-1", "amount": 42.0}]}


@app.get("/api/orders/{order_id}")
async def get_order(order_id: str):
    return {"id": order_id, "status": "shipped"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
