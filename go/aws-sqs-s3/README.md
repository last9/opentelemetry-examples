### Instrumenting AWS S3 and SQS using OpenTelemetry (Go)

This example demonstrates:
- Auto-instrumentation of AWS SDK v2 (S3 and SQS) via OpenTelemetry `otelaws` middleware
- End-to-end trace propagation across SQS using W3C context in `MessageAttributes`

It performs an S3 PutObject, sends an SQS message, receives it, extracts context, and starts a consumer span.

## Prerequisites
- Recent version of Go
- AWS credentials/region via the default chain OR LocalStack for local testing
- An OTLP endpoint (e.g., Last9) if you want to view traces

## Libraries
- AWS SDK for Go v2
- OpenTelemetry Go SDK
- `go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws`

## Traces
The app emits spans for:
- S3 PutObject
- SQS SendMessage
- SQS ReceiveMessage
- A custom consumer span: `process SQS message` (linked via W3C headers)

## Install dependencies
```bash
cd go/aws-sqs-s3
go mod tidy
```

## Exporting Telemetry Data to Last9
Set these environment variables before running:
```bash
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <BASIC_AUTH_TOKEN>"  # Last9 auth header
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"                  # Last9 OTLP endpoint
export OTEL_RESOURCE_ATTRIBUTES="service.name=aws-sqs-s3-demo"
```

## Running against AWS
Provide your bucket and queue URL:
```bash
export AWS_REGION=us-east-1
export S3_BUCKET=<your-bucket>
export SQS_QUEUE_URL=<your-sqs-queue-url>

go run .
```

## Local testing with LocalStack
Run LocalStack:
```bash
docker run -d --name localstack -p 4566:4566 -e SERVICES=s3,sqs localstack/localstack
```

Create resources using aws CLI (no awslocal needed):
```bash
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566

aws --endpoint-url "$AWS_ENDPOINT_URL" s3 mb s3://demo-bucket --region "$AWS_REGION" || true
aws --endpoint-url "$AWS_ENDPOINT_URL" sqs create-queue --queue-name demo-queue --region "$AWS_REGION" >/dev/null
export SQS_QUEUE_URL=$(aws --endpoint-url "$AWS_ENDPOINT_URL" sqs get-queue-url --queue-name demo-queue --region "$AWS_REGION" --query QueueUrl --output text)
export S3_BUCKET=demo-bucket
```

Run the app against LocalStack:
```bash
go run .
```

## Notes
- AWS SDK spans are auto-created by `otelaws` middleware added via `AppendMiddlewares(&cfg.APIOptions)`
- SQS trace propagation is manual: the app injects and extracts W3C headers via `MessageAttributes`
- Ensure `ReceiveMessage` uses `MessageAttributeNames=["All"]` so extraction works
- When `AWS_ENDPOINT_URL` is set (LocalStack), the app enables S3 path-style addressing automatically

## References
- OpenTelemetry Go Contrib (AWS SDK v2 `otelaws`): https://pkg.go.dev/go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws

