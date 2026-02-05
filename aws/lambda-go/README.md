# Go Lambda with OpenTelemetry - Last9 Integration

This example demonstrates how to instrument a Go AWS Lambda function with OpenTelemetry and send traces to Last9.

Unlike Python, Node.js, and Java which support **zero-code auto-instrumentation**, Go Lambda functions require:
- ✅ Manual tracer initialization in your code
- ✅ Custom collector configuration file
- ✅ Different layer type (`aws-otel-collector` instead of language-specific layer)

This example includes everything pre-configured! Just update `.env` and `collector-config.yaml` with your credentials - **no code changes needed**.

## Quick Start

### 1. Install Dependencies

```bash
go get go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-lambda-go/otellambda
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
go get go.opentelemetry.io/otel/sdk
go get google.golang.org/grpc
```

### 2. Write Your Lambda Function

Create `main.go`:

```go
package main

import (
    "context"
    "fmt"
    "log"
    "os"

    "github.com/aws/aws-lambda-go/lambda"
    "go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-lambda-go/otellambda"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)

type MyEvent struct {
    Name    string `json:"name"`
    Message string `json:"message"`
}

func HandleRequest(ctx context.Context, event MyEvent) (string, error) {
    return fmt.Sprintf("Hello %s! %s", event.Name, event.Message), nil
}

func initTracer() (*sdktrace.TracerProvider, error) {
    // CRITICAL: Export to localhost:4317 (local ADOT Collector)
    exporter, err := otlptracegrpc.New(context.Background(),
        otlptracegrpc.WithEndpoint("localhost:4317"),
        otlptracegrpc.WithInsecure(),
        otlptracegrpc.WithDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
    )
    if err != nil {
        return nil, fmt.Errorf("failed to create exporter: %w", err)
    }

    // Service name is read from OTEL_SERVICE_NAME environment variable
    serviceName := os.Getenv("OTEL_SERVICE_NAME")
    if serviceName == "" {
        serviceName = "go-lambda-otel-example" // fallback
    }

    res, _ := resource.New(context.Background(),
        resource.WithAttributes(semconv.ServiceName(serviceName)),
    )

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
        sdktrace.WithSampler(sdktrace.AlwaysSample()),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}

func main() {
    tp, err := initTracer()
    if err != nil {
        log.Fatalf("Failed to initialize tracer: %v", err)
    }
    defer tp.Shutdown(context.Background())

    // CRITICAL: WithFlusher ensures traces are sent before Lambda freezes
    lambda.Start(otellambda.InstrumentHandler(HandleRequest, otellambda.WithFlusher(tp)))
}
```

### 3. Create Collector Configuration

Create `collector-config.yaml`:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: localhost:4317
      http:
        endpoint: localhost:4318

exporters:
  otlp:
    endpoint: <YOUR_OTLP_ENDPOINT>:443  # NO https:// prefix!
    headers:
      authorization: Basic <your-base64-credentials>
    tls:
      insecure: false

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp]
```

### 4. Build and Package

```bash
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
zip function.zip bootstrap collector-config.yaml
```

### 5. Deploy to Lambda

```bash
# Create function (first time)
aws lambda create-function \
  --function-name your-function-name \
  --runtime provided.al2 \
  --role arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_LAMBDA_ROLE \
  --handler bootstrap \
  --zip-file fileb://function.zip \
  --region ap-south-1

# Add ADOT Collector layer
aws lambda update-function-configuration \
  --function-name your-function-name \
  --layers arn:aws:lambda:ap-south-1:901920570463:layer:aws-otel-collector-amd64-ver-0-117-0:1 \
  --region ap-south-1

# Set environment variables
aws lambda update-function-configuration \
  --function-name your-function-name \
  --environment "Variables={
    OTEL_SERVICE_NAME=your-service-name,
    OTEL_EXPORTER_OTLP_ENDPOINT=https://<YOUR_OTLP_ENDPOINT>:443,
    OTEL_EXPORTER_OTLP_HEADERS=authorization=Basic YOUR_CREDENTIALS,
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf,
    OTEL_TRACES_EXPORTER=otlp,
    OTEL_TRACES_SAMPLER=always_on,
    OTEL_PROPAGATORS=tracecontext\,baggage\,xray,
    OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,
    OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/collector-config.yaml
  }" \
  --region ap-south-1
```

### 6. Test

```bash
aws lambda invoke \
  --function-name your-function-name \
  --region ap-south-1 \
  --payload file://test-payload.json \
  response.json

cat response.json
```

### 7. View Traces in Last9

1. Log in to your Last9 dashboard
2. Navigate to **Traces**
3. Filter by service name
4. Traces appear within 1-2 minutes

## 🔑 Critical Implementation Notes

### Must-Do Items

1. **Runtime**: MUST use `provided.al2` (NOT `go1.x`)
2. **Tracer Init**: MUST initialize tracer with `localhost:4317` endpoint
3. **WithFlusher**: MUST use `otellambda.WithFlusher(tp)` or traces won't be sent
4. **Collector Config**: MUST include `collector-config.yaml` in deployment zip
5. **Endpoint Format**: Use `host:port` NOT `https://host:port` in collector config
6. **Header Format**: Environment variable MUST be `authorization=Basic ...` (key=value)
7. **Config File Path**: MUST set `OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/collector-config.yaml`

### Common Mistakes

❌ **Wrong**: `OTEL_EXPORTER_OTLP_HEADERS=Basic bGFzdDk6...`
✅ **Right**: `OTEL_EXPORTER_OTLP_HEADERS=authorization=Basic bGFzdDk6...`

❌ **Wrong**: `endpoint: https://<YOUR_OTLP_ENDPOINT>:443`
✅ **Right**: `endpoint: <YOUR_OTLP_ENDPOINT>:443`

❌ **Wrong**: `lambda.Start(otellambda.InstrumentHandler(HandleRequest))`
✅ **Right**: `lambda.Start(otellambda.InstrumentHandler(HandleRequest, otellambda.WithFlusher(tp)))`

## Architecture

```
Your Go Code → OTel SDK → localhost:4317 → ADOT Collector Layer → Last9
```

## Environment Variables Reference

| Variable | Required | Example |
|----------|----------|---------|
| `OTEL_SERVICE_NAME` | Yes | `my-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Yes | `https://<YOUR_OTLP_ENDPOINT>:443` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Yes | `authorization=Basic abc123==` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Yes | `http/protobuf` |
| `OTEL_TRACES_EXPORTER` | Yes | `otlp` |
| `OTEL_TRACES_SAMPLER` | Yes | `always_on` |
| `OTEL_PROPAGATORS` | Yes | `tracecontext,baggage,xray` |
| `OTEL_RESOURCE_ATTRIBUTES` | No | `deployment.environment=prod` |
| `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` | Yes | `/var/task/collector-config.yaml` |

**Note**: Do NOT use `AWS_LAMBDA_EXEC_WRAPPER` for Go (only for Python/Node/Java)

## Automated Deployment (Recommended)

This example includes a `deploy.sh` script that automates the entire deployment process. **No code changes required!**

```bash
# 1. Copy and configure environment variables
cp .env.example .env
# Edit .env with your AWS credentials and OTLP endpoint

# 2. Update collector-config.yaml with your OTLP endpoint and credentials

# 3. Deploy (handles everything: build, IAM, Lambda creation, layer, env vars)
chmod +x deploy.sh
./deploy.sh
```

The script automatically:
- ✅ Builds Go binary for Linux
- ✅ Creates deployment package with collector config
- ✅ Creates IAM role and policies
- ✅ Creates Lambda function with ADOT layer
- ✅ Sets all required environment variables

## Update Existing Function

```bash
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
zip function.zip bootstrap collector-config.yaml

aws lambda update-function-code \
  --function-name your-function-name \
  --zip-file fileb://function.zip \
  --region ap-south-1
```

## Troubleshooting

### No traces appearing in Last9

1. Check CloudWatch logs for errors: `aws logs tail /aws/lambda/your-function --follow`
2. Verify no "parse headers" errors
3. Verify "Starting GRPC server" message appears for traces
4. Confirm `collector-config.yaml` is in deployment package: `unzip -l function.zip`
5. Verify environment variables are set correctly

### "parse headers" error

The `OTEL_EXPORTER_OTLP_HEADERS` format is wrong. Must be: `authorization=Basic ...`

### Traces not sent before Lambda timeout

Missing `otellambda.WithFlusher(tp)` option in handler wrapper.

### "batch processor not found" error

The Lambda ADOT Collector doesn't support the batch processor. Remove it from `collector-config.yaml`.

## Files in This Example

```
.
├── main.go                      # Lambda function with OTel instrumentation
├── collector-config.yaml        # ADOT Collector configuration
├── go.mod                       # Go module dependencies
├── .env.example                 # Environment variable template
├── deploy.sh                    # Automated deployment script
├── test-payload.json            # Sample test event
├── .gitignore                   # Git ignore rules
└── README.md                    # This file
```

## Additional Resources

- [AWS ADOT Lambda Go Documentation](https://aws-otel.github.io/docs/getting-started/lambda/lambda-go/)
- [Last9 Documentation](https://last9.io/docs/)
- [Go Framework Integrations](https://last9.io/docs/integrations-opentelemetry-gin/)
