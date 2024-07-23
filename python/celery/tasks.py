from celery import Celery
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.celery import CeleryInstrumentor
import time

trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter()
span_processor = BatchSpanProcessor(otlp_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Create a Celery application
app = Celery('hello_world', broker='redis://localhost:6379/0')


CeleryInstrumentor().instrument()

app.conf.update(
    result_backend='redis://localhost:6379/1'
)

# Define a task
@app.task
def hello():
    time.sleep(3)
    return 'Hello, World!'


def main():
    while True:
        result = hello()
        print(f"Task called. Result: {result}")
        time.sleep(2)

if __name__ == '__main__':
    main()
