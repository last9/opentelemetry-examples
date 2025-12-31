# Go Gin on Cloud Run with OpenTelemetry

Fully instrumented Go Gin web application with OpenTelemetry sending traces, logs, and metrics to Last9.

## Features

- ✅ Automatic HTTP instrumentation via otelgin middleware
- ✅ Custom spans for business logic
- ✅ Structured JSON logging with trace correlation
- ✅ Custom metrics (request counter, latency histogram)
- ✅ Cloud Run resource detection
- ✅ Graceful shutdown with telemetry flush

## Quick Start

### Prerequisites

- Go 1.22+
- gcloud CLI
- Docker (for local testing)
- Last9 account with OTLP credentials

### Local Development

1. **Install dependencies**:
```bash
go mod download
```

2. **Set environment variables**:
```bash
export OTEL_SERVICE_NAME=gin-cloud-run-demo
export OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"
export PORT=8080
```

3. **Run locally**:
```bash
go run .
```

4. **Test endpoints**:
```bash
curl http://localhost:8080/
curl http://localhost:8080/users
curl http://localhost:8080/users/1
curl -X POST http://localhost:8080/users -H "Content-Type: application/json" -d '{"name":"Alice","email":"alice@example.com"}'
curl http://localhost:8080/error  # Generates error trace
```

### Deploy to Cloud Run

1. **Set variables**:
```bash
export PROJECT_ID=your-gcp-project
export REGION=us-central1
export SERVICE_NAME=gin-otel-demo
```

2. **Store Last9 credentials in Secret Manager**:
```bash
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-
```

3. **Deploy using Cloud Build**:
```bash
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=$SERVICE_NAME,_REGION=$REGION
```

4. **Or deploy directly**:
```bash
gcloud run deploy $SERVICE_NAME \
  --source . \
  --region $REGION \
  --set-env-vars OTEL_SERVICE_NAME=$SERVICE_NAME \
  --set-env-vars OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT \
  --set-secrets OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest \
  --allow-unauthenticated
```

### Verify in Last9

1. Get service URL:
```bash
gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'
```

2. Generate traffic:
```bash
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)')
curl $SERVICE_URL/users
```

3. Check Last9 dashboard for traces and metrics

## Architecture

### Telemetry Flow

```
Gin App → OTLP SDK → Last9
  ├─ Traces (HTTP requests, DB calls)
  ├─ Logs (JSON with trace correlation)
  └─ Metrics (request count, latency)
```

### Key Files

- `main.go` - Application logic and HTTP handlers
- `telemetry.go` - OpenTelemetry initialization
- `Dockerfile` - Multi-stage Docker build
- `cloudbuild.yaml` - Cloud Build configuration
- `service.yaml` - Cloud Run service manifest

## Instrumentation Details

### Automatic Instrumentation

The `otelgin` middleware automatically captures:
- HTTP method, route, status code
- Request/response headers (configurable)
- Span context propagation
- Error status on 5xx responses

### Custom Spans

Example from `main.go:209`:
```go
ctx, span := tracer.Start(ctx, "fetch_users_from_database",
    trace.WithAttributes(
        attribute.String("db.system", "postgresql"),
        attribute.String("db.operation", "SELECT"),
    ))
defer span.End()
```

### Structured Logging

Logs include trace correlation for Cloud Logging integration:
```go
structuredLog(ctx, "INFO", "User created", map[string]interface{}{
    "userName": input.Name,
})
```

Output:
```json
{
  "severity": "INFO",
  "message": "User created",
  "logging.googleapis.com/trace": "projects/PROJECT_ID/traces/TRACE_ID",
  "logging.googleapis.com/spanId": "SPAN_ID"
}
```

### Custom Metrics

**Request Counter** (`main.go:84`):
```go
requestCounter.Add(ctx, 1, metric.WithAttributes(
    attribute.String("http.method", c.Request.Method),
    attribute.String("http.route", c.FullPath()),
    attribute.Int("http.status_code", c.Writer.Status()),
))
```

**Latency Histogram** (`main.go:85`):
```go
requestLatency.Record(ctx, duration, metric.WithAttributes(...))
```

## Cloud Run Specific Features

### Resource Detection

`telemetry.go:42` automatically detects:
- Service name from `K_SERVICE`
- Revision from `K_REVISION`
- Region from `CLOUD_RUN_REGION`
- Project ID from `GOOGLE_CLOUD_PROJECT`

### Graceful Shutdown

`main.go:180` ensures telemetry is flushed before container stops:
```go
ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()
if err := srv.Shutdown(ctx); err != nil {
    log.Printf("Server shutdown error: %v", err)
}
```

## Troubleshooting

### Cold Start Timeouts

**Symptom**: Spans not appearing in Last9

**Solution**: Ensure shutdown timeout is sufficient:
```yaml
spec:
  template:
    spec:
      timeoutSeconds: 300  # service.yaml:14
```

### High Memory Usage

**Symptom**: Container OOM kills

**Solution**: Tune batch processor:
```go
sdktrace.WithBatcher(traceExporter,
    sdktrace.WithBatchTimeout(5*time.Second),
    sdktrace.WithMaxExportBatchSize(512),  // Reduce if needed
)
```

### Missing Trace Correlation in Logs

**Symptom**: Logs don't show in Last9 trace view

**Solution**: Ensure `GOOGLE_CLOUD_PROJECT` is set:
```bash
gcloud run services update $SERVICE_NAME \
  --update-env-vars GOOGLE_CLOUD_PROJECT=$PROJECT_ID
```

## Cost Optimization

| Resource | Configuration | Monthly Cost (estimate) |
|----------|---------------|------------------------|
| Cloud Run (min=0, max=10) | 256Mi, 1 CPU | ~$5-20 (depending on traffic) |
| Secret Manager | 1 secret | Free tier |
| Container Registry | ~100MB image | Free tier |

**Tips**:
- Use `--min-instances=0` to scale to zero during low traffic
- Set `--max-instances` to prevent runaway costs
- Monitor billable time via infrastructure metrics

## Next Steps

- [ ] Add database connection with instrumentation
- [ ] Implement distributed tracing across services
- [ ] Set up alerts in Last9
- [ ] Add custom business metrics
- [ ] Configure SLOs based on latency

## Resources

- [OpenTelemetry Go Docs](https://opentelemetry.io/docs/languages/go/)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Last9 Integration Guide](https://last9.io/docs/)
