# Python Lambda with AWS Chalice + ADOT - Last9 Integration

This example demonstrates how to instrument an AWS Chalice Python app with OpenTelemetry via the ADOT Lambda layer and send traces to Last9.

Chalice is AWS's Python serverless framework. ADOT provides **zero-code auto-instrumentation** -- no SDK init code needed. Just add the layer and environment variables to `.chalice/config.json`.

## Quick Start

### 1. Install Chalice

```bash
pip install chalice
```

### 2. Configure Credentials

```bash
cp .env.example .env
# Edit .env with your AWS credentials and Last9 OTLP endpoint
```

Update `collector-config.yaml` with your Last9 OTLP endpoint and credentials.

### 3. Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

The script copies `collector-config.yaml` into `.chalice/`, substitutes credentials, and runs `chalice deploy`.

### 4. Verify

```bash
# Get API URL
chalice url --stage dev

# Test
curl $(chalice url --stage dev)/
curl $(chalice url --stage dev)/items/42
curl -X POST $(chalice url --stage dev)/items -H "Content-Type: application/json" -d '{"name": "test"}'
```

Traces appear in Last9 within 1-2 minutes.

## Project Structure

```
.
├── app.py                     # Chalice app with routes, scheduler, OTel middleware
├── .chalice/
│   └── config.json            # Chalice config: ADOT layer, env vars, stages
├── collector-config.yaml      # ADOT Collector config (copied to .chalice/ at deploy)
├── requirements.txt           # chalice + opentelemetry-api only
├── deploy.sh                  # One-command deploy script
├── .env.example               # Credential template
├── .gitignore                 # Python + Chalice patterns
└── README.md                  # This file
```

## How It Works

```
Chalice App → ADOT Layer (auto-instruments) → localhost:4317 → ADOT Collector → Last9
```

1. `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument` wraps Python startup
2. ADOT layer injects OTel auto-instrumentation before Chalice loads
3. All route handlers, scheduled tasks, and AWS SDK calls are traced automatically
4. The in-Lambda ADOT Collector reads `collector-config.yaml` and exports to Last9

## X-Ray Co-existence

The config has `"xray": true` alongside ADOT. Both work simultaneously:

- X-Ray traces go to AWS X-Ray service (existing dashboards keep working)
- ADOT/OTLP traces go to Last9

`OTEL_PROPAGATORS=tracecontext,xray` ensures the ADOT layer reads both W3C `traceparent` and AWS `X-Amzn-Trace-Id` headers. Trace context propagates correctly regardless of format.

To disable X-Ray, remove `"xray": true` from config.json and set `OTEL_PROPAGATORS=tracecontext`.

## Environment Variables Reference

| Variable | Required | Example |
|----------|----------|---------|
| `AWS_LAMBDA_EXEC_WRAPPER` | Yes | `/opt/otel-instrument` |
| `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` | Yes | `/var/task/.chalice/collector-config.yaml` |
| `OTEL_SERVICE_NAME` | Yes | `my-chalice-service` |
| `OTEL_PROPAGATORS` | Yes | `tracecontext,xray` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Yes | `http/protobuf` |
| `OTEL_TRACES_EXPORTER` | Yes | `otlp` |
| `OTEL_TRACES_SAMPLER` | Yes | `always_on` or `traceidratio` |
| `OTEL_TRACES_SAMPLER_ARG` | If traceidratio | `0.1` (10%) |
| `OTEL_RESOURCE_ATTRIBUTES` | No | `deployment.environment=prod` |

## Critical Notes

1. **No batch processor**: Lambda ADOT does NOT support the `batch` processor. Do not add it to collector-config.yaml.
2. **collector-config.yaml must be in .chalice/**: Chalice packages that directory with the Lambda. The deploy script handles this.
3. **Do NOT add opentelemetry-sdk to requirements.txt**: The ADOT layer provides it. Only `opentelemetry-api` is needed (for custom spans).
4. **Endpoint format**: Use `host:port` in collector-config.yaml (gRPC). No `https://` prefix.
5. **Header format**: Must be `authorization=Basic ...` (lowercase key, key=value format).

## Troubleshooting

### No traces in Last9

1. Check CloudWatch Logs: `aws logs tail /aws/lambda/otel-chalice-example-dev --follow`
2. Verify collector-config.yaml is in the deployment: check for ADOT initialization messages
3. Confirm Last9 credentials are valid

### "batch processor not found"

Remove `batch` processor from collector-config.yaml. Lambda ADOT doesn't support it.

### "Module not found" for opentelemetry

Do NOT add `opentelemetry-sdk` or `opentelemetry-instrumentation-*` to requirements.txt. The ADOT layer provides them.

### High cold start latency

ADOT adds ~500ms-1s. Increase memory to 256MB+ or use provisioned concurrency.
