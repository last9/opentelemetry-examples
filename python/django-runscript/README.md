# Django Script OpenTelemetry Instrumentation with Circus Process Manager

This example demonstrates how to add OpenTelemetry auto-instrumentation and custom span tracing to Django management scripts using `django-extensions`, `runscript`, and Circus process manager. The implementation includes automatic initialization with fallbacks and comprehensive error handling.

## Requirements
- Django
- django-extensions
- Circus process manager
- OpenTelemetry packages (see below)

## Installation

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```
   
   Or install manually:
   ```bash
   pip install Django django-extensions circus opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-distro requests
   ```

2. **Install OpenTelemetry instrumentation packages automatically:**
   ```bash
   opentelemetry-bootstrap -a install
   ```
   This will install all available auto-instrumentation packages for your environment.

3. **Create your traced Django script:**
   Place your script in `your_app/scripts/your_script.py` and use the robust tracing module:

   **your_app/scripts/your_script.py**
   ```python
   import os
   os.environ.setdefault("DJANGO_SETTINGS_MODULE", "your_project.settings")

   from your_app.tracing import traced_function, log_trace_status
   from opentelemetry.trace import SpanKind
   import requests
   from your_app.models import Example

   @traced_function(include_args=True)
   def sub_operation():
       print("Doing sub operation")

   @traced_function(span_kind=SpanKind.CONSUMER, include_args=True)
   def run():
       # Optional: Log trace status for debugging
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
   ```

## Key Features

### **Auto-Bootstrap**
- **Auto-initialization**: OpenTelemetry initializes automatically when tracing module is imported
- **Intelligent fallbacks**: Uses console exporter when OTLP endpoint unreachable
- **Smart service naming**: Auto-detects service name from Django settings
- **Error handling**: Never crashes your application, continues execution on tracing failures
- **Health checking**: Tests OTLP endpoint connectivity with detailed status logging

### **Enhanced Tracing Decorator**
- **OTel Semantic Conventions**: Follows official semantic conventions for `code.function`, `code.namespace`, etc.
- **Graceful degradation**: Falls back to no-op spans when tracing fails
- **Rich span attributes**: Includes function metadata, arguments, and results
- **Exception handling**: Proper exception recording and span status management

### **Production Debugging**
- **Status reporting**: `log_trace_status()` shows exactly what's configured
- **HTTP Status logging**: Comprehensive logging for all response codes (200s, 400s, 500s)
- **Configuration validation**: Warns about missing endpoints, headers, etc.

## Circus Process Manager Setup

4. **Configure environment variables in circus.ini:**
   The `circus.ini` file is already configured with the necessary OpenTelemetry environment variables. Update the following values as needed:
   
   ```ini
   env.OTEL_SERVICE_NAME = django-runscript-example
   env.OTEL_EXPORTER_OTLP_ENDPOINT = http://your-otel-collector:4317  # Update with your endpoint
   env.OTEL_EXPORTER_OTLP_HEADERS = authorization=Bearer your-token-here  # Update with your headers
   env.OTEL_RESOURCE_ATTRIBUTES = deployment.environment=local
   ```

5. **Start the Django script with Circus:**
   ```bash
   # Start circus daemon
   circusd circus.ini
   
   # Or run in foreground for debugging
   circusd --log-level debug circus.ini
   ```

6. **Control the process with circus commands:**
   ```bash
   # Check status
   circusctl status
   
   # Stop the script
   circusctl stop django-script
   
   # Start the script
   circusctl start django-script
   
   # Restart the script
   circusctl restart django-script
   
   # Stop circus completely
   circusctl quit
   ```

## Manual Execution (Alternative)

If you prefer to run the script manually without Circus:

**With virtual environment:**
```bash
source venv/bin/activate
PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings opentelemetry-instrument python manage.py runscript hello_world
```

**With system-wide installation:**
```bash
PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings opentelemetry-instrument python manage.py runscript hello_world
```

## Deployment Notes

The circus configuration uses system-wide executables (`opentelemetry-instrument` and `python`). For different deployment scenarios:

**Docker/Container deployments:**
- Ensure OpenTelemetry packages are installed in the container
- The current configuration should work as-is

**Virtual environment deployments:**
- Update circus.ini to use full paths:
  ```ini
  cmd = /path/to/venv/bin/opentelemetry-instrument /path/to/venv/bin/python manage.py runscript hello_world
  ```

**System-wide installations:**
- Current configuration works with globally installed packages

## Notes
- **Circus Process Manager**: Provides robust process management, automatic restarts, and better logging for production deployments
- **OpenTelemetry Integration**: The decorator provided will create a parent span of kind `CONSUMER` with the span name as `<file>:<function>` for the entrypoint, and `INTERNAL` for other decorated functions
- **Auto-instrumentation**: All auto-instrumented operations (Django ORM, requests, etc.) will be traced as children of these spans
- **Custom Spans**: You can add manual child spans as needed for custom operations, but for DB and HTTP calls, auto-instrumentation is sufficient
- **Logging**: Enhanced logging configuration in Django settings provides better integration with Circus process management

## Circus Configuration Details

The `circus.ini` file includes:
- **Process Management**: Automatic restart on failure, single process execution
- **Environment Variables**: All necessary OpenTelemetry configuration
- **Logging**: Proper stdout/stderr handling for better debugging
- **Working Directory**: Correctly set for Django project structure

## SQS Processing with LocalStack

This example also includes SQS message processing with OpenTelemetry tracing using LocalStack for local development and testing.

### LocalStack Setup

7. **Start LocalStack with SQS service:**
   ```bash
   docker-compose -f docker-compose.localstack.yml up -d
   ```

8. **Set up SQS queue and send test messages:**
   ```bash
   python setup_localstack_sqs.py
   ```

### Running SQS Processor

**Manual execution:**
```bash
# Set LocalStack environment variables
export AWS_ENDPOINT_URL=http://localhost:4566
export SQS_QUEUE_URL=http://localhost:4566/000000000000/django-test-queue
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

# Run SQS processor with OpenTelemetry
PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings opentelemetry-instrument python manage.py runscript sqs_processor
```

**With Circus process manager:**
Update `circus.ini` to include AWS/LocalStack environment variables:
```ini
[env]
DJANGO_SETTINGS_MODULE = mysite.settings
AWS_ENDPOINT_URL = http://localhost:4566
SQS_QUEUE_URL = http://localhost:4566/000000000000/django-test-queue
AWS_REGION = us-east-1
AWS_ACCESS_KEY_ID = test
AWS_SECRET_ACCESS_KEY = test
MAX_ITERATIONS = 10
SQS_POLLING_DELAY = 5
```

Then update the watcher command:
```ini
[watcher:sqs-processor]
cmd = opentelemetry-instrument python manage.py runscript sqs_processor
```

### Automated Testing

Run the complete test with automated setup:
```bash
./test_localstack_sqs.sh
```

This script will:
- Start LocalStack
- Install dependencies  
- Create SQS queue and send test messages
- Run the SQS processor with OpenTelemetry tracing
- Clean up when finished

### SQS Processor Features

The `sqs_processor.py` script includes:
- **OpenTelemetry Integration**: Full tracing for SQS operations with proper span kinds
- **LocalStack Support**: Works with both LocalStack and real AWS SQS
- **Message Processing**: JSON message handling with error recovery
- **Configurable Polling**: Environment-based configuration for delays and iterations
- **Robust Error Handling**: Continues processing even if individual messages fail

### Volume Directory

The `volume/` directory is used by LocalStack to persist data between container restarts. It's automatically created and managed by Docker Compose and is not required for the basic integration to work.

## References
- [OpenTelemetry Python Documentation](https://opentelemetry-python.readthedocs.io/)
- [django-extensions runscript docs](https://django-extensions.readthedocs.io/en/latest/runscript.html)
- [Circus Process Manager Documentation](https://circus.readthedocs.io/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/) 