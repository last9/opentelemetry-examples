import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

from hello.tracing import traced_function
from opentelemetry.trace import SpanKind
import requests
from hello.models import Example

@traced_function()
def sub_operation():
    print("Doing sub operation")

@traced_function(span_kind=SpanKind.CONSUMER)
def run():
    print("Hello World")
    sub_operation()
    # DB call example (auto-instrumented)
    obj, created = Example.objects.get_or_create(name="OpenTelemetry Example")
    print(f"DB object: {obj.name}, created: {created}")
    # External HTTP call example (auto-instrumented)
    response = requests.get("https://httpbin.org/get")
    print(f"External call status: {response.status_code}")
