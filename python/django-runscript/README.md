# Django AWS SQS Auto-Instrumentation with OpenTelemetry + Circus

Automatic instrumentation for Django applications using AWS SQS with OpenTelemetry - including automatic trace context propagation.

---

## How to Implement in Your Django Application with Circus

### 1. Install Packages

```bash
pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-instrumentation-botocore
```

### 2. Copy Tracing Module

Copy `hello/tracing.py` to your Django app (e.g., `myapp/tracing.py`). No modifications needed.

**Note (production-ready behavior):**
- Works with both `boto3.client(...)` and `boto3.Session().client(...)` (customers often use custom sessions)
- Automatically injects W3C trace context (`traceparent`, `tracestate`) into SQS `MessageAttributes` on send
- Automatically enriches SQS spans with queue metadata extracted from `QueueUrl`

### 3. Initialize in Django

Add to your app's `apps.py`:

```python
# myapp/apps.py
from django.apps import AppConfig

class MyAppConfig(AppConfig):
    name = 'myapp'

    def ready(self):
        from myapp.tracing import initialize_otel
        initialize_otel()
```

### 4. Configure Circus

Add OpenTelemetry env vars to your `circus.ini`:

**Single Worker Example:**
```ini
[watcher:your-worker]
cmd = python manage.py your_command
working_dir = .
numprocesses = 1
autostart = true
autorestart = true

[env:your-worker]
DJANGO_SETTINGS_MODULE = myproject.settings

# Required
OTEL_SERVICE_NAME = my-django-app
OTEL_EXPORTER_OTLP_ENDPOINT = https://otlp.last9.io:443
OTEL_EXPORTER_OTLP_HEADERS = Authorization=Basic YOUR_LAST9_API_KEY_HERE
OTEL_TRACES_EXPORTER = otlp

# Recommended
OTEL_RESOURCE_ATTRIBUTES = deployment.environment=production,service.version=1.0.0

# Recommended sampling (defaults are prod-friendly, override if needed)
OTEL_TRACES_SAMPLER = parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG = 0.1

# Debug-only (do NOT enable in prod unless you really want console spans)
# OTEL_CONSOLE_FALLBACK = true
# OTEL_BOOTSTRAP_TEST_SPAN = true
# OTEL_BOOTSTRAP_CONNECTIVITY_TEST = true
```

**Multiple Workers Example:**
```ini
[watcher:sqs-consumer]
cmd = python manage.py process_queue
# ... other settings

[env:sqs-consumer]
DJANGO_SETTINGS_MODULE = myproject.settings
OTEL_SERVICE_NAME = my-app-consumer
OTEL_EXPORTER_OTLP_ENDPOINT = http://your-otel-collector:4317

[watcher:sqs-producer]
cmd = python manage.py send_messages
# ... other settings

[env:sqs-producer]
DJANGO_SETTINGS_MODULE = myproject.settings
OTEL_SERVICE_NAME = my-app-producer
OTEL_EXPORTER_OTLP_ENDPOINT = http://your-otel-collector:4317
```

### 5. Done! Your Existing Code Works

All boto3 SQS operations are now automatically traced:

```python
# Your existing code - no changes needed!
sqs = boto3.client('sqs')

# ✅ Auto-traced as "SQS.SendMessage" + trace context auto-injected
sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(data))

# ✅ Auto-traced as "SQS.ReceiveMessage"
response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)

# ✅ Auto-traced as "SQS.DeleteMessage"
sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)
```

### 6. (Optional) Link Consumer to Producer Traces

Add in your SQS consumer to link traces:

```python
from opentelemetry import propagate, context

for message in response.get('Messages', []):
    # Extract trace context
    carrier = {k: v['StringValue'] for k, v in message.get('MessageAttributes', {}).items()
               if isinstance(v, dict) and 'StringValue' in v}

    if carrier:
        parent_context = propagate.extract(carrier)
        token = context.attach(parent_context)
        try:
            process_message(message['Body'])
        finally:
            context.detach(token)
    else:
        process_message(message['Body'])
```

**That's it!** All AWS operations (SQS, S3, DynamoDB, Lambda, etc.) are automatically traced with full context propagation.

### What Gets Auto-Instrumented

| AWS Service | Operations | Span Name Example | Attributes Captured |
|-------------|-----------|-------------------|---------------------|
| **SQS** | SendMessage, ReceiveMessage, DeleteMessage, SendMessageBatch | `SQS.SendMessage` | Queue URL, Message ID, Request ID, Region |
| **S3** | GetObject, PutObject, ListBuckets | `S3.GetObject` | Bucket, Key, Request ID, Region |
| **DynamoDB** | GetItem, PutItem, Query, Scan | `DynamoDB.GetItem` | Table, Request ID, Region |
| **Lambda** | Invoke, InvokeAsync | `Lambda.Invoke` | Function name, Request ID, Region |
| **All AWS** | Any boto3 operation | `{Service}.{Operation}` | Service-specific attributes |

**Additional automatic features:**
- ✅ Trace context injection on SQS SendMessage/SendMessageBatch
- ✅ AWS attributes (Queue URLs, ARNs, IDs) captured automatically
- ✅ Exceptions/errors recorded in spans
- ✅ Works with Django ORM, HTTP requests if instrumented

### Configuration Reference

**Required Environment Variables:**
```bash
OTEL_SERVICE_NAME=my-service              # Service name
OTEL_EXPORTER_OTLP_ENDPOINT=http://...    # Collector endpoint (OTLP)
```

**Optional Environment Variables:**
```bash
OTEL_EXPORTER_OTLP_PROTOCOL=grpc                             # grpc | http/protobuf
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer token        # OTLP headers (auth, etc.)
# If your backend uses a separate traces endpoint:
# OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://.../v1/traces

OTEL_RESOURCE_ATTRIBUTES=deployment.environment=prod         # Resource tags
OTEL_TRACES_EXPORTER=otlp                                   # Default: otlp
OTEL_METRICS_EXPORTER=otlp                                  # If exporting metrics too
OTEL_LOGS_EXPORTER=otlp                                     # If exporting logs too

OTEL_PROPAGATORS=tracecontext,baggage                        # W3C propagation (default)

OTEL_TRACES_SAMPLER=parentbased_traceidratio                # Sampling strategy
OTEL_TRACES_SAMPLER_ARG=0.1                                 # 10% (example)
OTEL_LOG_LEVEL=info                                         # Log level

# OTLP export tuning (optional)
OTEL_EXPORTER_OTLP_TIMEOUT=10s                               # Export timeout
OTEL_EXPORTER_OTLP_COMPRESSION=gzip                          # gzip | none
OTEL_EXPORTER_OTLP_INSECURE=true                             # Mainly for grpc + plain HTTP collectors

# Debug-only (off by default in prod)
OTEL_CONSOLE_FALLBACK=true                                  # Add console exporter only when enabled
OTEL_BOOTSTRAP_TEST_SPAN=true                               # Emit a one-time startup test span
OTEL_BOOTSTRAP_CONNECTIVITY_TEST=true                       # Test OTLP endpoint connectivity at startup

# SQS receive convenience (enabled by default)
OTEL_SQS_AUTO_INCLUDE_MESSAGE_ATTRIBUTES=true                # Ensure ReceiveMessage requests MessageAttributes=["All"]
```

### Verification

After restarting Circus, check logs for:
```
INFO: Initializing OTEL for service: my-django-app
INFO: Botocore instrumentation enabled with automatic SQS context propagation
INFO: OpenTelemetry initialized successfully
DEBUG: Auto-injected trace context into SQS SendMessage: ['traceparent', 'tracestate']
```

### Troubleshooting

**No traces appearing:**
- Verify `OTEL_EXPORTER_OTLP_ENDPOINT` is correct and reachable
- Check `initialize_otel()` is called in `apps.py`
- Ensure AppConfig is registered in `INSTALLED_APPS`

**SQS operations not traced:**
- Verify `opentelemetry-instrumentation-botocore` is installed
- Check logs for instrumentation initialization messages

**Distributed tracing not working:**
- Ensure you attach extracted context in your consumer (see below)
- (By default) `MessageAttributeNames=['All']` is automatically added for `ReceiveMessage` so trace context is actually returned
- Verify context extraction is implemented in consumer
- Check both producer/consumer use same OTLP endpoint

---

## Example Repository Details

This repository contains a complete working example with:
- Django + django-extensions + runscript pattern
- Circus process manager configuration
- LocalStack for SQS testing
- Producer/Consumer examples with automatic trace propagation

### Installation

```bash
pip install -r requirements.txt
```

### Start LocalStack (for testing)

```bash
docker-compose -f docker-compose.localstack.yml up -d
python setup_localstack_sqs.py
```

### Run the Producer

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export SQS_QUEUE_URL=http://localhost:4566/000000000000/django-test-queue
PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings python manage.py runscript sqs_producer
```

### Run the Consumer

```bash
PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings python manage.py runscript sqs_processor
```

### Run with Circus

```bash
circusd circus.ini
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
- **Custom Spans**: You can add manual child spans as needed for custom operations, but for DB, HTTP, and AWS SDK calls, auto-instrumentation is sufficient
- **AWS SDK Auto-Instrumentation**: All boto3 operations (SQS, S3, DynamoDB, etc.) are automatically traced with rich AWS-specific attributes
- **Automatic Distributed Tracing**: Context propagation through SQS MessageAttributes is fully automatic via instrumentation hooks - just like Java!
- **Logging**: Enhanced logging configuration in Django settings provides better integration with Circus process management

## Circus Configuration Details

The `circus.ini` file includes:
- **Process Management**: Automatic restart on failure, single process execution
- **Environment Variables**: All necessary OpenTelemetry configuration
- **Logging**: Proper stdout/stderr handling for better debugging
- **Working Directory**: Correctly set for Django project structure

## AWS SDK Auto-Instrumentation with Botocore

This example demonstrates **automatic instrumentation for boto3/botocore** (AWS SDK for Python), eliminating the need for manual span creation for AWS service calls.

### How It Works

The `opentelemetry-instrumentation-botocore` package automatically instruments all boto3 operations:

**Installation:**
```bash
pip install opentelemetry-instrumentation-botocore
```

**Automatic Initialization:**
The tracing module (`hello/tracing.py`) automatically instruments botocore with context propagation hooks:
```python
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor

# Instrumented with request/response hooks for automatic context propagation
BotocoreInstrumentor().instrument(
    request_hook=sqs_request_hook,   # Auto-injects trace context
    response_hook=sqs_response_hook   # Logs context extraction
)
```

**What Gets Auto-Instrumented:**
- ✅ **SQS Operations**: `send_message`, `receive_message`, `delete_message`, `send_message_batch`
- ✅ **S3 Operations**: `get_object`, `put_object`, `list_buckets`
- ✅ **DynamoDB Operations**: `get_item`, `put_item`, `query`, `scan`
- ✅ **Lambda Invocations**: `invoke`, `invoke_async`
- ✅ **All other AWS services** supported by boto3

**Automatic Span Attributes:**
Each AWS operation span automatically includes:
- `rpc.system`: "aws-api"
- `rpc.service`: Service name (e.g., "SQS", "S3", "DynamoDB")
- `rpc.method`: Operation name (e.g., "ReceiveMessage", "SendMessage")
- `aws.region`: AWS region
- `aws.request_id`: AWS request ID from response
- Service-specific attributes (queue URL, bucket name, table name, etc.)

### SQS Example Comparison

**Before (Manual Instrumentation):**
```python
@traced_function(span_kind=SpanKind.CONSUMER)
def receive_message(queue_url, sqs):
    response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)
    return response
```

**After (Auto-Instrumentation):**
```python
# No decorator needed! Botocore auto-instrumentation handles it
response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10)
# Automatically creates span: "SQS.ReceiveMessage" with all AWS attributes
```

### 🎉 Automatic Context Propagation for Distributed Tracing

**Injection is automatic** via botocore hooks: `traceparent`/`tracestate` are added to SQS `MessageAttributes` on send.

**Extraction/linking is still done in your consumer logic** (each message has its own parent context), but the SDK is configured to request message attributes so you reliably receive `traceparent`.

**How It Works:**

The implementation uses **request/response hooks** in botocore instrumentation to automatically handle trace context:

1. **On Send** (`SendMessage`, `SendMessageBatch`):
   - Hooks automatically inject trace context (`traceparent`, `tracestate`) into `MessageAttributes`
   - Your custom `MessageAttributes` are preserved and merged with trace context
   - Works for both single and batch operations

2. **On Receive** (`ReceiveMessage`):
   - Trace context is returned in `MessageAttributes` (the SDK requests them automatically)
   - Your consumer attaches the extracted context before processing to link traces

**Producer Side** (`sqs_producer.py`):
```python
# Just call send_message normally - context is auto-injected!
sqs.send_message(
    QueueUrl=queue_url,
    MessageBody=json.dumps(data)
)
# ✅ Trace context automatically added to MessageAttributes by hooks

# Or with custom attributes - they're merged automatically:
sqs.send_message(
    QueueUrl=queue_url,
    MessageBody=json.dumps(data),
    MessageAttributes={'Priority': {'StringValue': 'high', 'DataType': 'String'}}
)
# ✅ Both Priority AND trace context (traceparent/tracestate) are sent!
```

**Consumer Side** (`sqs_processor.py`):
```python
# Extract trace context from message for distributed tracing
parent_context = extract_trace_context_from_message(message)

if parent_context:
    # Link consumer span to producer span
    token = context.attach(parent_context)
    try:
        process_message_business_logic(message['Body'])
    finally:
        context.detach(token)
```

**Note:** While injection is fully automatic, extraction still needs to be done in the message processing loop because each message can have a different trace context.

---

## Enhanced SQS Attribute Capture with Last9 Integration

This implementation includes **comprehensive automatic attribute capture** for all SQS operations, following OpenTelemetry semantic conventions. All attributes are extracted automatically from boto3 SDK interactions - no manual configuration required!

### What's Captured Automatically

#### Queue Metadata (All Operations)
Extracted automatically from the queue URL:
- `aws.sqs.queue.url` - Full SQS queue URL
- `messaging.destination.name` - Queue name
- `server.address` - SQS endpoint hostname (AWS or LocalStack)
- `server.port` - SQS endpoint port
- `messaging.sqs.queue.account_id` - AWS account ID
- `messaging.sqs.queue.region` - AWS region (for AWS endpoints)

#### SendMessage Operation
Request attributes:
- `messaging.operation.name` = "send"
- `messaging.operation.type` = "send"
- `messaging.sqs.message.body_size` - Message body length in bytes
- `messaging.sqs.message.delay_seconds` - Delay if specified
- `messaging.sqs.message.custom_attributes_count` - Count of custom MessageAttributes
- `messaging.sqs.message.messagetype` - Custom MessageType attribute (if present)
- `messaging.sqs.message.priority` - Custom Priority attribute (if present)
- `messaging.sqs.message.source` - Custom Source attribute (if present)

Response attributes:
- `messaging.message.id` - SQS MessageId
- `messaging.sqs.message.id` - SQS MessageId (duplicate for compatibility)
- `messaging.sqs.message.md5_of_body` - MD5 checksum of message body
- `messaging.sqs.message.sequence_number` - Sequence number (FIFO queues only)
- `aws.request_id` - AWS request identifier
- `http.status_code` - HTTP response status

#### ReceiveMessage Operation
Request attributes:
- `messaging.operation.name` = "receive"
- `messaging.operation.type` = "receive"
- `messaging.sqs.receive.max_messages` - MaxNumberOfMessages parameter
- `messaging.sqs.receive.wait_time_seconds` - WaitTimeSeconds parameter
- `messaging.sqs.receive.visibility_timeout` - VisibilityTimeout parameter

Response attributes (when messages received):
- `messaging.sqs.receive.message_count` - Number of messages received
- `messaging.sqs.receive.total_body_size` - Total size of all message bodies
- `messaging.message.id` - First message ID (representative)
- `messaging.sqs.message.sent_timestamp` - When message was sent to SQS
- `messaging.sqs.message.approximate_receive_count` - Number of times message received
- `messaging.sqs.message.approximate_first_receive_timestamp` - First receive time
- `messaging.sqs.message.custom_attributes_count` - Count of custom attributes
- `messaging.sqs.message.messagetype` - Custom MessageType (if present)
- `messaging.sqs.message.priority` - Custom Priority (if present)
- `aws.request_id` - AWS request identifier
- `http.status_code` - HTTP response status

#### DeleteMessage Operation
- `messaging.operation.name` = "settle"
- `messaging.operation.type` = "settle"
- `aws.request_id` - AWS request identifier
- `http.status_code` - HTTP response status

#### SendMessageBatch Operation
Request attributes:
- `messaging.operation.name` = "send"
- `messaging.operation.type` = "send"
- `messaging.sqs.batch.size` - Number of messages in batch
- `messaging.sqs.batch.total_body_size` - Sum of all message body sizes

Response attributes:
- `messaging.sqs.batch.success_count` - Number of successful sends
- `messaging.sqs.batch.failed_count` - Number of failed sends
- `messaging.sqs.batch.failure_codes` - Comma-separated failure codes (if any failures)
- `aws.request_id` - AWS request identifier
- `http.status_code` - HTTP response status

### Last9 Setup

Last9 is a managed OpenTelemetry backend that provides powerful trace analysis and observability.

#### 1. Get Your Last9 API Key

1. Sign up at [last9.io](https://last9.io)
2. Navigate to Settings → API Keys
3. Create a new API key for OpenTelemetry ingestion
4. Copy the API key (format: Base64 encoded string)

#### 2. Configure Environment Variables

Create or update the `.env` file in your project root:

```bash
# OpenTelemetry Configuration for Last9
OTEL_SERVICE_NAME=django-sqs-integration
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io:443
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic YOUR_LAST9_API_KEY_HERE
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.version=1.0.0
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp

# AWS Configuration (use your actual AWS credentials for production)
AWS_REGION=us-east-1
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/YOUR_QUEUE_NAME
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
```

**For LocalStack testing:**
```bash
# Use LocalStack endpoint
AWS_ENDPOINT_URL=http://localhost:4566
SQS_QUEUE_URL=http://localhost:4566/000000000000/django-test-queue
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
```

#### 3. Load Environment Variables

```bash
# Load all environment variables
export $(cat .env | xargs)
```

#### 4. Run Your Application

```bash
# Activate virtual environment
source venv/bin/activate

# Run producer
python manage.py runscript sqs_producer

# Run consumer
python manage.py runscript sqs_processor
```

#### 5. View Traces in Last9

1. Log in to your Last9 dashboard
2. Navigate to **Traces** or **APM**
3. Filter by service name: `django-sqs-integration`
4. You'll see spans for:
   - `SQS.SendMessage` - Producer operations
   - `SQS.ReceiveMessage` - Consumer operations
   - `SQS.DeleteMessage` - Message deletion
   - Custom spans from your business logic

### Using Attributes in Last9

The captured attributes enable powerful observability capabilities:

**Filter by Queue:**
```
messaging.destination.name = "django-test-queue"
```

**Find High-Priority Messages:**
```
messaging.sqs.message.priority = "high"
```

**Track Message Sizes:**
```
messaging.sqs.message.body_size > 1000
```

**Monitor Batch Operations:**
```
messaging.sqs.batch.size > 5
```

**Identify Failed Batches:**
```
messaging.sqs.batch.failed_count > 0
```

**Track by Region:**
```
messaging.sqs.queue.region = "us-east-1"
```

**Monitor Receive Counts:**
```
messaging.sqs.message.approximate_receive_count > 1
```

### Distributed Tracing

The implementation automatically creates distributed traces linking producer and consumer spans:

1. **Producer** sends message with trace context (automatic)
2. **SQS** stores message with MessageAttributes containing trace context
3. **Consumer** extracts trace context and links to producer trace
4. **Last9** shows the complete message lifecycle in a single trace

**In Last9:**
- Click on any `SQS.SendMessage` span
- See the linked `SQS.ReceiveMessage` span in the same trace
- View the complete flow: Send → Queue → Receive → Process → Delete

### OpenTelemetry Semantic Conventions

This implementation follows official OpenTelemetry semantic conventions:

- [Messaging Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/messaging/)
- [SQS Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/messaging/sqs/)

**Standard Attributes:**
- `messaging.operation.name` - Operation name (send, receive, process, settle)
- `messaging.operation.type` - Operation type (send, receive)
- `messaging.destination.name` - Queue name
- `messaging.message.id` - Message identifier
- `server.address` - Server hostname
- `server.port` - Server port
- `http.status_code` - HTTP response status

**AWS-Specific Attributes:**
- `aws.sqs.queue.url` - Full queue URL
- `aws.request_id` - AWS request identifier
- `messaging.sqs.*` - SQS-specific attributes

### Troubleshooting Last9 Integration

**Traces not appearing in Last9:**
1. Verify API key is correct in `OTEL_EXPORTER_OTLP_HEADERS`
2. Check endpoint: `https://otlp.last9.io:443`
3. Ensure network connectivity to Last9
4. Check application logs for initialization messages

**Missing attributes:**
1. Ensure you're using the updated `hello/tracing.py`
2. Verify botocore instrumentation is enabled (check logs for "Botocore instrumentation enabled")
3. Check OpenTelemetry version compatibility

**Distributed tracing not working:**
1. Ensure consumer uses `MessageAttributeNames=['All']` in `receive_message()`
2. Verify context extraction in consumer (see `sqs_processor.py` example)
3. Check both producer and consumer send to same Last9 endpoint

**Performance impact:**
- Attribute capture adds minimal overhead (~1-2ms per operation)
- Uses efficient span attribute setting
- No blocking I/O during attribute capture
- All attribute extraction happens after AWS SDK calls complete

---

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

### SQS Scripts

**`sqs_processor.py` (Consumer)**:
- **Auto-Instrumented SQS Operations**: All `receive_message` and `delete_message` calls are automatically traced
- **Context Propagation**: Extracts trace context from message attributes to link producer and consumer traces
- **LocalStack Support**: Works with both LocalStack and real AWS SQS
- **Configurable Polling**: Environment-based configuration for delays and iterations
- **Robust Error Handling**: Continues processing even if individual messages fail

**`sqs_producer.py` (Producer)**:
- **Auto-Instrumented SQS Operations**: All `send_message` and `send_message_batch` calls are automatically traced
- **Automatic Context Propagation**: Trace context is automatically injected into MessageAttributes via hooks (no manual work!)
- **Custom Attributes Support**: Your business MessageAttributes are automatically merged with trace context
- **Batch Operations**: Each message in a batch gets its own trace context automatically
- **LocalStack Support**: Works with both LocalStack and real AWS SQS

### Running the Producer

```bash
# Set environment variables
export AWS_ENDPOINT_URL=http://localhost:4566
export SQS_QUEUE_URL=http://localhost:4566/000000000000/django-test-queue
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

# Run producer with OpenTelemetry
PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings opentelemetry-instrument python manage.py runscript sqs_producer
```

### Volume Directory

The `volume/` directory is used by LocalStack to persist data between container restarts. It's automatically created and managed by Docker Compose and is not required for the basic integration to work.

## References
- [OpenTelemetry Python Documentation](https://opentelemetry-python.readthedocs.io/)
- [django-extensions runscript docs](https://django-extensions.readthedocs.io/en/latest/runscript.html)
- [Circus Process Manager Documentation](https://circus.readthedocs.io/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/) 