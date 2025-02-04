from django.conf import settings
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import (
    OTLPMetricExporter,
)
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
    OTLPSpanExporter,
)
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


bind = "127.0.0.1:8000"

# Sample Worker processes
workers = 4
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2

# Sample logging
errorlog = "-"
loglevel = "info"
accesslog = "-"
access_log_format = (
    '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'
)


def post_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

   # Initialize tracing
    tracer_provider = TracerProvider()
    trace.set_tracer_provider(tracer_provider)
    trace.get_tracer_provider().add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter())
    )

    # Initialize metrics
    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(),
        export_interval_millis=getattr(settings, 'OTEL_METRIC_EXPORT_INTERVAL', 60000)
    )
    meter_provider = MeterProvider(metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)