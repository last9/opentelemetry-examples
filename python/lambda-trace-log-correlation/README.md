# AWS Lambda Trace-Log Correlation with OpenTelemetry

This example demonstrates how to achieve complete traces-log-traces correlation in AWS Lambda using OpenTelemetry, with logs collected via CloudWatch and correlated with traces in your observability platform.

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Lambda    │ ──────> │  OTLP        │ ──────> │ Observability│
│  Function   │ traces  │  Endpoint    │         │  Platform   │
└─────────────┘         └──────────────┘         └─────────────┘
       │                                                  ▲
       │ logs                                             │
       ▼                                                  │
┌─────────────┐         ┌──────────────┐                │
│ CloudWatch  │ ──────> │ OTel         │ ────────────────┘
│    Logs     │         │ Collector    │    logs with
└─────────────┘         └──────────────┘    trace_id

```

## Key Features

- **Custom Trace Logging**: Uses a custom `TraceContextFormatter` to inject `trace_id` and `span_id` into every log message
- **Manual OTLP Export**: Direct trace export to observability platform without Lambda Layer conflicts
- **CloudWatch Log Collection**: OTel Collector polls CloudWatch logs and extracts trace context
- **Trace ID Extraction**: Automatic extraction of trace_id and span_id as separate log attributes for correlation

## Prerequisites

- AWS account with Lambda and CloudWatch access
- EC2 instance for running OTel Collector (with IAM role for CloudWatch Logs read access)
- Observability platform with OTLP endpoint supporting traces and logs

## Setup

### 1. Lambda Function

**Dependencies** (`requirements.txt`):
```txt
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-exporter-otlp-proto-http==1.21.0
```

**Lambda Configuration**:
- Runtime: Python 3.11
- Handler: `lambda_function.lambda_handler`
- Environment Variables:
  - `OTEL_EXPORTER_OTLP_ENDPOINT`: Your OTLP endpoint (e.g., `https://otlp-region.example.com:443`)
  - `OTEL_SERVICE_NAME`: Service name for traces (e.g., `lambda-trace-correlation`)

**Deployment**:
```bash
# Create deployment package
zip -r lambda-package.zip lambda_function.py
cd venv/lib/python3.11/site-packages
zip -r ../../../../lambda-package.zip .
cd ../../../../

# Deploy to Lambda
aws lambda update-function-code \
  --function-name your-lambda-function \
  --zip-file fileb://lambda-package.zip
```

### 2. OTel Collector Setup

**Install OTel Collector** on EC2 instance:
```bash
# Download and install
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.114.0/otelcol-contrib_0.114.0_linux_amd64.tar.gz
tar -xzf otelcol-contrib_0.114.0_linux_amd64.tar.gz
sudo mv otelcol-contrib /usr/local/bin/
```

**IAM Role** for EC2 instance:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

**Configure OTel Collector**:
Copy `otel-collector-config.yaml` to your EC2 instance and update:
- `region`: Your AWS region
- `named`: Your Lambda log group name (e.g., `/aws/lambda/your-function-name`)
- `endpoint`: Your OTLP endpoint
- `Authorization`: Your OTLP authorization header

**Start Collector**:
```bash
nohup /usr/local/bin/otelcol-contrib --config /path/to/otel-collector-config.yaml > otel.log 2>&1 &
```

## How It Works

### 1. Trace Context Injection

The Lambda function uses a custom logging formatter to inject trace context:

```python
class TraceContextFormatter(logging.Formatter):
    def format(self, record):
        span = trace.get_current_span()
        if span:
            span_context = span.get_span_context()
            if span_context.is_valid:
                record.trace_id = format(span_context.trace_id, '032x')
                record.span_id = format(span_context.span_id, '016x')
        return super().format(record)
```

This produces logs like:
```
[INFO] [trace_id=38372e92ab741e4f1033d84c4de56ee9 span_id=06199b7a707b3ae7] Lambda invocation started
```

### 2. Trace Export

Traces are exported directly to the OTLP endpoint using manual initialization:

```python
def init_tracer():
    resource = Resource.create({
        "service.name": os.environ.get("OTEL_SERVICE_NAME", "lambda-service"),
        "deployment.environment": "production"
    })

    provider = TracerProvider(resource=resource)

    otlp_exporter = OTLPSpanExporter(
        endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT") + "/v1/traces",
        headers={"authorization": "..."}
    )

    _span_processor = BatchSpanProcessor(otlp_exporter)
    provider.add_span_processor(_span_processor)
    trace.set_tracer_provider(provider)
```

### 3. Log Collection and Correlation

The OTel Collector:
1. Polls CloudWatch logs every 2 minutes (configurable)
2. Extracts `trace_id` and `span_id` from log body using regex:
   ```yaml
   transform/extract_trace_id:
     log_statements:
       - context: log
         statements:
           - set(attributes["trace_id"], ExtractPatterns(body, "trace_id=(?P<trace_id>[a-f0-9]{32})")["trace_id"])
           - set(attributes["span_id"], ExtractPatterns(body, "span_id=(?P<span_id>[a-f0-9]{16})")["span_id"])
   ```
3. Exports logs with trace_id as separate attributes to observability platform

## Verification

### Test Lambda Function

```bash
aws lambda invoke \
  --function-name your-lambda-function \
  --payload '{"test":"trace-correlation"}' \
  response.json
```

### Check CloudWatch Logs

Look for logs with trace context:
```
[INFO] [trace_id=38372e92ab741e4f1033d84c4de56ee9 span_id=06199b7a707b3ae7] Processing test event
```

### Verify OTel Collector

Check collector logs to confirm trace_id extraction:
```bash
tail -f otel.log | grep trace_id
```

You should see:
```
Attributes:
     -> trace_id: Str(38372e92ab741e4f1033d84c4de56ee9)
     -> span_id: Str(06199b7a707b3ae7)
```

### Check Observability Platform

In your observability platform:
1. Find a trace by trace_id
2. Navigate to logs view
3. Filter by `trace_id` attribute
4. Verify logs from the same trace appear

## Important Notes

### Force Flush Pattern

Lambda containers can be frozen after execution, so we force flush traces:

```python
if _span_processor:
    _span_processor.force_flush(timeout_millis=5000)
```

This ensures all traces are sent before the Lambda execution completes.

### Why Manual Initialization?

We use manual OTLP initialization instead of AWS Lambda Layer because:
- Avoids TracerProvider override conflicts
- Full control over trace export configuration
- No dependency on Lambda Layer version compatibility

### Log Format Requirements

The regex pattern in OTel Collector expects exact format:
```
trace_id=<32-hex-chars> span_id=<16-hex-chars>
```

If you change the log format in Lambda, update the regex in `otel-collector-config.yaml`.

## Related Examples

- [AWS SQS Lambda](../aws-sqs-lambda/): Lambda with SQS integration
- [AWS Lambda Go](../../aws/lambda-go/): Lambda trace export in Go

## References

- [OpenTelemetry Python SDK](https://opentelemetry-python.readthedocs.io/)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)
- [OpenTelemetry Transformation Language (OTTL)](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/pkg/ottl)
- [AWS CloudWatch Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/awscloudwatchreceiver)
