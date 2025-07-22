# Django Script OpenTelemetry Instrumentation Example

This example demonstrates how to add OpenTelemetry auto-instrumentation and custom span tracing to Django management scripts using `django-extensions` and `runscript`.

## Requirements
- Django
- django-extensions
- OpenTelemetry packages (see below)

## Installation

1. **Install dependencies:**
   ```bash
   pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-distro
   ```

2. **Install OpenTelemetry instrumentation packages automatically:**
   ```bash
   opentelemetry-bootstrap -a install
   ```
   This will install all available auto-instrumentation packages for your environment.

3. **Update the script to get traced:**
   Place your script in `your_app/scripts/your_script.py` and use the tracing decorator from a separate file (e.g., `your_app/tracing.py`):
   
   **your_app/tracing.py**
   ```python
   from opentelemetry import trace
   from opentelemetry.trace import SpanKind
   import os

   tracer = trace.get_tracer(__name__)

   def traced_function(span_kind=SpanKind.INTERNAL):
       def decorator(func):
           def wrapper(*args, **kwargs):
               file_name = os.path.basename(__file__)
               span_name = f"{file_name}:{func.__name__}"
               with tracer.start_as_current_span(span_name, kind=span_kind):
                   return func(*args, **kwargs)
           return wrapper
       return decorator
   ```

   **your_app/scripts/your_script.py**
   ```python
   import os
   os.environ.setdefault("DJANGO_SETTINGS_MODULE", "your_project.settings")

   from your_app.tracing import traced_function
   from opentelemetry.trace import SpanKind
   import requests
   from your_app.models import Example

   def sub_operation():
       print("Doing sub operation")

   @traced_function(span_kind=SpanKind.CONSUMER)  # Entry point span is CONSUMER
   def run():
       print("Hello World")
       sub_operation()
       # DB call example (auto-instrumented)
       obj, created = Example.objects.get_or_create(name="OpenTelemetry Example")
       print(f"DB object: {obj.name}, created: {created}")
       # External HTTP call example (auto-instrumented)
       response = requests.get("https://httpbin.org/get")
       print(f"External call status: {response.status_code}")
   ```
   - The entrypoint function (`run`) uses `span_kind=SpanKind.CONSUMER`.
   - Any other function you want to trace can use `@traced_function()` (defaults to INTERNAL):
   
   ```python
   @traced_function()  # SpanKind.INTERNAL by default
   def helper():
       print("This is a helper function.")
   ```

4. Set environment variables
```shell
export OTEL_SERVICE_NAME=<service_name>
export OTEL_EXPORTER_OTLP_ENDPOINT=<last9_endpoint>
export OTEL_EXPORTER_OTLP_HEADERS="<last9_otlp_header>"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
export OTEL_TRACES_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp
export OTEL_TRACES_SAMPLER="always_on"
```

5. **Run your script with OpenTelemetry auto-instrumentation:**
   ```bash
   source venv/bin/activate
   PYTHONPATH=. DJANGO_SETTINGS_MODULE=your_project.settings opentelemetry-instrument python manage.py runscript your_script
   ```

## Notes
- The decorator provided will create a parent span of kind `CONSUMER` with the span name as `<file>:<function>` for the entrypoint, and `INTERNAL` for other decorated functions.
- All auto-instrumented operations (Django ORM, requests, etc.) will be traced as children of these spans.
- You can add manual child spans as needed for custom operations, but for DB and HTTP calls, auto-instrumentation is sufficient.

## References
- [OpenTelemetry Python Documentation](https://opentelemetry-python.readthedocs.io/)
- [django-extensions runscript docs](https://django-extensions.readthedocs.io/en/latest/runscript.html) 