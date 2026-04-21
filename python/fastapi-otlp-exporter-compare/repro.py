"""
Repro driver: emit span, idle past nginx keepalive_timeout (5s), emit again.
Second export hits half-closed socket on HTTP exporter → RemoteDisconnected.
gRPC mode stays healthy via HTTP/2 keepalive pings.

Run:
  # HTTP mode (reproduces):
  OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \\
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \\
  python repro.py

  # gRPC mode (stable):
  OTEL_EXPORTER_OTLP_PROTOCOL=grpc \\
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \\
  python repro.py
"""
import os
import time
import logging

logging.basicConfig(level=logging.INFO)

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

PROTOCOL = os.getenv("OTEL_EXPORTER_OTLP_PROTOCOL", "http/protobuf").lower()
ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

if PROTOCOL == "grpc":
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    exporter = OTLPSpanExporter(endpoint=ENDPOINT, insecure=True)
else:
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    exporter = OTLPSpanExporter(endpoint=f"{ENDPOINT.rstrip('/')}/v1/traces")

provider = TracerProvider(resource=Resource.create({"service.name": "repro"}))
# Short schedule so flushes happen per iteration
processor = BatchSpanProcessor(exporter, schedule_delay_millis=500)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)


def emit(label: str):
    with tracer.start_as_current_span(f"span-{label}"):
        pass
    provider.force_flush(timeout_millis=5000)
    print(f"[{label}] flushed")


print(f"protocol={PROTOCOL} endpoint={ENDPOINT}")
emit("warmup")
print("sleeping 15s (past nginx keepalive_timeout=5s)…")
time.sleep(15)
emit("after-idle-1")
time.sleep(15)
emit("after-idle-2")

provider.shutdown()
print("done")
