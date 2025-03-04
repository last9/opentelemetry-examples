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
import asyncio
import aiohttp
from django.http import JsonResponse

# Initialize tracer at module level
tracer = trace.get_tracer(__name__)

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

# Async helper functions
async def fetch_api_data(session, url, api_name):
    """Helper function to fetch data from an API endpoint"""
    with tracer.start_as_current_span(f"fetch_{api_name}") as span:
        try:
            async with session.get(url) as response:
                span.set_attribute("http.url", url)
                span.set_attribute("http.status_code", response.status)
                return await response.json()
        except Exception as e:
            span.set_attribute("error", str(e))
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            return {"error": str(e)}

def async_view(func):
    """Decorator to handle async views"""
    def wrapper(request, *args, **kwargs):
        return asyncio.run(func(request, *args, **kwargs))
    return wrapper

@async_view
async def multi_api_call(request):
    """View to demonstrate concurrent API calls using asyncio.gather"""
    with tracer.start_as_current_span("multi_api_call") as span:
        try:
            # Define API endpoints
            apis = [
                ("todos", "https://jsonplaceholder.typicode.com/todos/1"),
                ("posts", "https://jsonplaceholder.typicode.com/posts/1"),
                ("users", "https://jsonplaceholder.typicode.com/users/1")
            ]
            
            # Create session and execute concurrent requests
            async with aiohttp.ClientSession() as session:
                tasks = [
                    fetch_api_data(session, url, api_name) 
                    for api_name, url in apis
                ]
                
                # Use asyncio.gather to run requests concurrently
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                # Combine results
                response_data = {
                    api_name: result 
                    for (api_name, _), result in zip(apis, results)
                }
                
                # Add telemetry data
                span.set_attribute("api_count", len(apis))
                span.set_attribute("successful_calls", sum(1 for r in results if "error" not in r))
                
                return JsonResponse(response_data)
                
        except Exception as e:
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            span.set_attribute("error", str(e))
            return JsonResponse(
                {"error": "Internal server error", "details": str(e)}, 
                status=500
            )