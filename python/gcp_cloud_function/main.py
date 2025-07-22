import asyncio
import functions_framework
from flask import Request, jsonify
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.instrumentation.asyncio import AsyncioInstrumentor

# Initialize OpenTelemetry components
def initialize_tracing():
    # Create a resource with service information
    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: "cloud-function",
        ResourceAttributes.SERVICE_VERSION: "0.1.0",
    })

    # Set up tracer provider with the resource
    provider = TracerProvider(resource=resource)
    trace.set_tracer_provider(provider)

    # Configure the OTLP exporter
    otlp_exporter = OTLPSpanExporter(
        endpoint={{ .Logs.WriteURL }},
        headers={
            "authorization":"{{ .Logs.AuthValue }}",
        }
    )

    #span_processor = BatchSpanProcessor(ConsoleSpanExporter())
    span_processor = BatchSpanProcessor((otlp_exporter))
    provider.add_span_processor(span_processor)

    AsyncioInstrumentor().instrument()

    return trace.get_tracer(__name__)

tracer = initialize_tracing()

async def process_request(request_data):
    with tracer.start_as_current_span("process_request") as span:
        span.set_attribute("request.data_size", len(str(request_data)))

        await asyncio.sleep(1)

        result = {"message": "Processed asynchronously", "data": request_data}
        return result

@functions_framework.http
def http_handler(request: Request):
    with tracer.start_as_current_span("http_handler", kind=trace.SpanKind.SERVER) as span:
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.url", request.url)
        span.set_attribute("http.route", request.path)

        if request.is_json:
            request_data = request.get_json()
        else:
            request_data = request.form.to_dict() if request.form else request.args.to_dict()

        with tracer.start_as_current_span("extract_headers") as header_span:
            headers = dict(request.headers)
            header_span.set_attribute("request.header_count", len(headers))

            if 'traceparent' in headers:
                header_span.set_attribute("trace.parent_id", headers['traceparent'])

        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(process_request(request_data))
            loop.close()

            return jsonify(result)
        except Exception as e:
            with tracer.start_as_current_span("error_handler") as error_span:
                error_span.set_attribute("error.type", str(type(e).__name__))
                error_span.set_attribute("error.message", str(e))
                error_span.record_exception(e)

            return jsonify({"error": str(e)}), 500

# For local testing
if __name__ == "__main__":
    import os

    # Run the app locally with functions-framework
    # Use: functions-framework --target http_handler --debug
    print("Run with: functions-framework --target http_handler --debug")