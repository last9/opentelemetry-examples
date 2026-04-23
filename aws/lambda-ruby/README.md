# Ruby Lambda with OpenTelemetry - Last9 Integration

Instrument a Ruby AWS Lambda function with OpenTelemetry and send traces to Last9.

Unlike Python, Node.js, and Java — Ruby has no AWS-managed ADOT language layer. Instead:
- ✅ Direct OTLP export from the Ruby OTel SDK (no collector sidecar needed)
- ✅ `opentelemetry-instrumentation-aws_lambda` auto-creates the root invocation span
- ✅ `opentelemetry-instrumentation-aws_sdk` auto-instruments S3, SES, SQS, DynamoDB calls
- ✅ `force_flush` in `ensure` block guarantees spans ship before Lambda freezes

## Trace Hierarchy

```
lambda_handler (auto — AwsLambda instrumentation)
  └─ process_event (manual span)
       └─ S3.GetObject (auto — AwsSdk instrumentation)
```

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
# Edit .env — fill in OTLP endpoint and credentials from app.last9.io/integrations/opentelemetry
```

### 2. Install Dependencies

```bash
bundle install
```

### 3. Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

### 4. Test

```bash
aws lambda invoke \
  --function-name ruby-lambda-otel-example \
  --region ap-south-1 \
  --payload file://test-payload.json \
  response.json

cat response.json
```

### 5. View Traces

Open [app.last9.io/traces](https://app.last9.io/traces) and filter by your service name.

## How It Works

### `setup_otel.rb`

Initializes the OTel SDK once. The `return if defined?(OTEL_TRACER)` guard prevents
double-initialization when tests load their own exporter before this file runs.

```ruby
require 'opentelemetry/instrumentation/aws_lambda'
require 'opentelemetry/instrumentation/aws_sdk'

OpenTelemetry::SDK.configure do |c|
  c.use 'OpenTelemetry::Instrumentation::AwsLambda'  # auto root span
  c.use 'OpenTelemetry::Instrumentation::AwsSdk'      # auto S3/SES/SQS spans
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new
    )
  )
end
```

### `lambda_function.rb`

The handler calls `force_flush` in `ensure` — this is critical:

```ruby
def lambda_handler(event:, context:)
  # ... your logic ...
ensure
  OpenTelemetry.tracer_provider.force_flush
end
```

## Environment Variables

| Variable | Required | Example |
|----------|----------|---------|
| `OTEL_SERVICE_NAME` | Yes | `ruby-lambda-example` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Yes | `https://otlp-aps1.last9.io:443` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Yes | `Authorization=Basic abc123==` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Yes | `http/protobuf` |
| `OTEL_TRACES_SAMPLER` | Yes | `always_on` |
| `OTEL_PROPAGATORS` | No | `tracecontext,baggage,xray` |
| `OTEL_RESOURCE_ATTRIBUTES` | No | `deployment.environment=production` |

## Packaging Gems

Lambda requires gems pre-bundled. The deploy script handles this automatically:

```bash
bundle config set --local path 'vendor/bundle'
bundle install
zip -qr function.zip lambda_function.rb setup_otel.rb Gemfile Gemfile.lock vendor/
```

## Troubleshooting

### No traces in Last9

1. Check CloudWatch logs: `aws logs tail /aws/lambda/your-function --follow`
2. Verify `force_flush` is in the `ensure` block
3. Check `OTEL_EXPORTER_OTLP_HEADERS` format: must be `Authorization=Basic ...` (key=value)

### `Cannot load such file` errors

Gems not bundled into the zip. Run `bundle install` before `deploy.sh`.

### Header format

```
# Wrong
OTEL_EXPORTER_OTLP_HEADERS=Basic bGFzdDk6...

# Right
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic bGFzdDk6...
```

## Files

```
.
├── lambda_function.rb   # Lambda handler with manual spans
├── setup_otel.rb        # OTel SDK initialization (idempotent)
├── Gemfile              # Dependencies
├── .env.example         # Environment variable template
├── deploy.sh            # Automated deployment script
├── test-payload.json    # Sample test event
└── README.md
```

## Additional Resources

- [Last9 OpenTelemetry Documentation](https://last9.io/docs/integrations/cloud-providers/aws-lambda)
- [opentelemetry-instrumentation-aws_lambda](https://github.com/open-telemetry/opentelemetry-ruby-contrib/tree/main/instrumentation/aws_lambda)
- [opentelemetry-instrumentation-aws_sdk](https://github.com/open-telemetry/opentelemetry-ruby-contrib/tree/main/instrumentation/aws_sdk)
