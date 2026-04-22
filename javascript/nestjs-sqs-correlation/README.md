# NestJS SQS Polling — OpenTelemetry Trace Correlation

NestJS service that polls SQS at fixed intervals and correlates all logs and spans within a single poll cycle and per individual message.

## Trace Structure

```
[sqs.poll_cycle]                  ← INTERNAL span, one per interval tick
  ├── [<queue> receive]           ← CONSUMER span, auto by AwsInstrumentation
  ├── [<queue> process]           ← CONSUMER span, per message (manual)
  │     ├── link → producer trace ← cross-trace link to the sending service
  │     ├── [your business logic] ← child spans (HTTP, DB, downstream SQS)
  │     └── [SQS.DeleteMessage]   ← auto by AwsInstrumentation
  └── [<queue> process]           ← parallel per message
```

Every log line emitted during message processing includes `trace_id` and `span_id` fields, allowing log-to-trace correlation in Last9.

## Prerequisites

- Node.js >= 20
- AWS credentials with SQS access (or LocalStack for local testing)
- Last9 OTLP endpoint and credentials

## Quick Start

```bash
cp .env.example .env
# Edit .env with your SQS URL and Last9 credentials

npm install
npm run start:dev
```

### Local Testing with LocalStack

```bash
docker compose up localstack otel-collector
# Then start the app:
npm run start:dev
```

Send a test message:
```bash
aws --endpoint-url=http://localhost:4566 sqs send-message \
  --queue-url http://localhost:4566/000000000000/demo-queue \
  --message-body '{"type":"test","data":"hello"}'
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `SQS_QUEUE_URL` | Full SQS queue URL | required |
| `SQS_QUEUE_NAME` | Queue name (used as span name) | required |
| `AWS_REGION` | AWS region | `us-east-1` |
| `SQS_WAIT_TIME_SECONDS` | Long-poll wait (0-20s) | `5` |
| `POLL_INTERVAL_MS` | Delay between poll cycles | `5000` |
| `SQS_ENDPOINT` | Override endpoint (LocalStack) | — |
| `OTEL_SERVICE_NAME` | Service name in traces | `nestjs-sqs-subscriber` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | required |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers for OTLP | required |

## Key Implementation Details

### Poll Cycle Span
`SqsPollerService.pollOnce()` creates a root `sqs.poll_cycle` span wrapping the entire interval tick. All receive and process spans are children. Use this to correlate "why did this poll take long?" with the batch it processed.

### Per-Message Spans
Each `Message` from a `ReceiveMessageCommand` response gets its own `SPAN_KIND_CONSUMER` child span. This lets you see individual message latency, failures, and log lines separately — critical when processing batches of 10.

### Producer Context Linking
If the message sender uses `AwsInstrumentation` (which auto-injects `traceparent` into `MessageAttributes`), the consumer extracts that context and adds it as a **span link** — not a parent. This creates two independent trace trees (producer's + consumer's) that can navigate to each other in Last9.

`MessageAttributeNames: ['All']` in `ReceiveMessageCommand` is required for this to work.

### Log Correlation
`getTraceContext()` reads the active span's `traceId` and `spanId` and injects them into log objects. In Last9, filter logs by `trace_id` to see all logs from a single message's processing.

## Verification

After starting, you should see in Last9:
1. **Traces**: `sqs.poll_cycle` spans appearing at your poll interval
2. **Child spans**: `<queue> process` spans for each received message
3. **Logs**: Log entries with `trace_id` field matching the trace in the UI

## References

- [Last9 OTLP setup](https://docs.last9.io)
- [@opentelemetry/instrumentation-aws-sdk](https://www.npmjs.com/package/@opentelemetry/instrumentation-aws-sdk)
- [OTel Messaging Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/messaging/)
