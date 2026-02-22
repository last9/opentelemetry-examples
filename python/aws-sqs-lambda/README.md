# SQS → Lambda Trace Propagation (Python)

End-to-end distributed tracing across SQS and Lambda using OpenTelemetry W3C TraceContext.

```
Publisher Service ──▶ SQS ──(Event Source Mapping)──▶ Lambda Consumer
     (Flask)          │                                    │
     span: /publish   │   traceparent in MessageAttributes │
     span: send_to_sqs│                                    span: process queue
                      └────────────────────────────────────┘
                              Same Trace ID
```

## Problem

When a service sends messages to SQS and Lambda consumes them via Event Source Mapping, the Lambda spans appear as **separate traces** instead of being linked to the producer's trace. This happens because SQS does not natively forward HTTP trace headers — you must manually inject/extract W3C context via `MessageAttributes`.

## How It Works

**Producer side** (`producer.py`):
```python
from opentelemetry.propagate import inject

carrier = {}
inject(carrier)  # Writes traceparent + tracestate into carrier

# Add as SQS MessageAttributes
sqs.send_message(
    QueueUrl=QUEUE_URL,
    MessageBody=body,
    MessageAttributes={
        key: {"DataType": "String", "StringValue": value}
        for key, value in carrier.items()
    },
)
```

**Lambda consumer side** (`lambda_function.py`):
```python
from opentelemetry.propagate import extract

# SQS ESM delivers attributes with lowercase keys
carrier = {}
for key, attr in record["messageAttributes"].items():
    carrier[key] = attr.get("stringValue") or attr.get("StringValue")

ctx = extract(carrier)

with tracer.start_as_current_span("process", context=ctx, kind=SpanKind.CONSUMER):
    # This span is now a child of the producer's trace
    ...
```

## Prerequisites

- Python 3.10+
- AWS account with SQS and Lambda access
- [Last9](https://app.last9.io) account for viewing traces
- Docker (for local testing)

## Quick Start

### 1. Install dependencies

```bash
cd python/aws-sqs-lambda
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your Last9 OTLP credentials and AWS settings
```

### 3. Local test with LocalStack

```bash
chmod +x test_local.sh
./test_local.sh
```

This starts LocalStack, creates a queue, runs the Flask producer, sends a test message, and verifies that `traceparent` appears in the SQS MessageAttributes.

### 4. Deploy Lambda to AWS

```bash
chmod +x deploy.sh
./deploy.sh
```

### 5. Test end-to-end

```bash
# Start the producer locally (or deploy it)
export SQS_QUEUE_URL=<your-real-queue-url>
python app.py

# In another terminal, send a message
curl -X POST http://localhost:8080/publish \
  -H "Content-Type: application/json" \
  -d '{"action": "upload", "file": "report.csv"}'

# Check Last9 → Traces: both publisher-service and lambda-consumer
# spans should appear under the same Trace ID
```

### 6. Test Lambda directly with a simulated SQS event

```bash
aws lambda invoke \
  --function-name sqs-lambda-otel-consumer \
  --region us-east-1 \
  --payload file://test-event.json \
  response.json && cat response.json
```

## Configuration

### Producer (Flask app)

| Variable | Required | Example |
|----------|----------|---------|
| `SQS_QUEUE_URL` | Yes | `https://sqs.us-east-1.amazonaws.com/123/my-queue` |
| `OTEL_SERVICE_NAME` | Yes | `publisher-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Yes | `https://otlp.last9.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Yes | `authorization=Basic <credentials>` |
| `AWS_ENDPOINT_URL` | No | `http://localhost:4566` (LocalStack) |

### Lambda consumer

| Variable | Required | Example |
|----------|----------|---------|
| `AWS_LAMBDA_EXEC_WRAPPER` | Yes | `/opt/otel-instrument` |
| `OTEL_SERVICE_NAME` | Yes | `lambda-consumer` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Yes | `https://otlp.last9.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Yes | `authorization=Basic <credentials>` |
| `OTEL_PROPAGATORS` | Yes | `tracecontext,baggage` |
| `OTEL_TRACES_SAMPLER` | Yes | `always_on` |

## Verification

After sending a message through the producer and having Lambda process it:

1. Go to [Last9 Traces](https://app.last9.io)
2. Search by the **Trace ID** from the producer's logs
3. You should see spans from **both** `publisher-service` and `lambda-consumer` under the same trace waterfall

If Lambda spans still appear as separate traces, check:
- Producer is injecting `traceparent` into `MessageAttributes` (not message body)
- Lambda handler is extracting from `record["messageAttributes"]` with lowercase `stringValue`
- ADOT layer is attached and `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument` is set
- `OTEL_PROPAGATORS=tracecontext,baggage` is configured on the Lambda

<details>
<summary>SQS ESM attribute format gotcha</summary>

When Lambda is triggered via SQS Event Source Mapping, message attributes use **lowercase** keys:

```json
{"traceparent": {"stringValue": "00-abc...", "dataType": "String"}}
```

But the AWS SDK `ReceiveMessage` API returns **PascalCase**:

```json
{"traceparent": {"StringValue": "00-abc...", "DataType": "String"}}
```

The `lambda_function.py` in this example handles both formats.
</details>

## Files

```
.
├── app.py                  # Flask producer service
├── producer.py             # SQS send with trace context injection
├── lambda_function.py      # Lambda handler with trace context extraction
├── deploy.sh               # Lambda deployment script
├── test_local.sh           # End-to-end local test with LocalStack
├── test-event.json         # Sample SQS ESM event for Lambda testing
├── docker-compose.yaml     # LocalStack + producer for local dev
├── Dockerfile              # Producer container image
├── requirements.txt        # Producer dependencies
├── requirements-lambda.txt # Lambda-only dependencies (if not using ADOT)
├── .env.example            # Environment variable template
└── .gitignore
```
