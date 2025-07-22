import uwsgidecorators
from django.conf import settings
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.django import DjangoInstrumentor

@uwsgidecorators.postfork
def init_telemetry():
    # Add OpenTelemetry middleware if not present
    if not hasattr(settings, 'MIDDLEWARE'):
        settings.MIDDLEWARE = []
    otel_middleware = 'opentelemetry.instrumentation.django.middleware.OpenTelemetryMiddleware'
    if otel_middleware not in settings.MIDDLEWARE:
        settings.MIDDLEWARE.insert(0, otel_middleware)

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
