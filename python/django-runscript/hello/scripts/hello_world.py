import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

from hello.tracing import traced_function, log_trace_status, initialize_otel
from opentelemetry.trace import SpanKind
import requests
from hello.models import Example

@traced_function(include_args=True)
def sub_operation():
    print("Doing sub operation")

@traced_function(span_kind=SpanKind.CONSUMER, include_args=True)
def run():
    # Log trace status for debugging
    status = log_trace_status()
    print(f"OpenTelemetry Status: {status}")
    
    print("Hello World")
    sub_operation()
    
    # DB call example (auto-instrumented)
    obj, created = Example.objects.get_or_create(name="OpenTelemetry Example")
    print(f"DB object: {obj.name}, created: {created}")
    
    # External HTTP call example (auto-instrumented)
    try:
        response = requests.get("https://httpbin.org/get", timeout=5)
        print(f"External call status: {response.status_code}")
    except Exception as e:
        print(f"External call failed: {e}")
    
    print("Script completed successfully")
