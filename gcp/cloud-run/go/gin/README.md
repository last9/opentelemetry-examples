# Instrumenting Gin application on Cloud Run using OpenTelemetry

This example demonstrates how to integrate OpenTelemetry with a Gin web application deployed to Google Cloud Run. The implementation provides automatic HTTP instrumentation, structured logging with trace correlation, custom metrics, and runtime metrics exported to Last9 via OTLP.

## Prerequisites

- Go 1.22+
- Google Cloud SDK (`gcloud`)
- [Last9](https://app.last9.io) account with OTLP credentials

## Installation

1. Install dependencies:

```bash
go mod download
```

2. Obtain the OTLP endpoint and Auth Header from the [Last9 dashboard](https://app.last9.io).

3. Set environment variables:

```bash
export OTEL_SERVICE_NAME=gin-cloud-run-demo
export OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"
export PORT=8080
```

## Running the Application

### Local Development

1. Run the application:

```bash
go run .
```

2. Test the endpoints:

```bash
# Home
curl http://localhost:8080/

# Get all users
curl http://localhost:8080/users

# Get specific user
curl http://localhost:8080/users/1

# Create user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice","email":"alice@example.com"}'

# Test error handling
curl http://localhost:8080/error
```

Once the server is running, you can access the application at `http://localhost:8080` by default. The API endpoints are:

- GET `/` - Home page with service info
- GET `/users` - List all users
- GET `/users/:id` - Get user by ID
- POST `/users` - Create new user
- GET `/error` - Test error handling

### Deploy to Cloud Run

1. Set variables:

```bash
export PROJECT_ID=your-gcp-project
export REGION=us-central1
export SERVICE_NAME=gin-otel-demo
```

2. Store Last9 credentials in Secret Manager:

```bash
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-
```

3. Deploy using Cloud Build:

```bash
gcloud builds submit --config cloudbuild.yaml \
  --substitutions=_SERVICE_NAME=$SERVICE_NAME,_REGION=$REGION,_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
```

4. Or deploy directly:

```bash
gcloud run deploy $SERVICE_NAME \
  --source . \
  --region $REGION \
  --set-env-vars OTEL_SERVICE_NAME=$SERVICE_NAME \
  --set-env-vars OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT \
  --set-secrets OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest \
  --allow-unauthenticated
```

## Verify in Last9

### Generate Traffic

```bash
# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)')

# Send test requests
for i in {1..10}; do
  curl -s "$SERVICE_URL/users" > /dev/null
  sleep 1
done
```

### View Telemetry in Last9

1. Navigate to [Last9 APM Dashboard](https://app.last9.io/)
2. Filter by service name to see traces, logs, and metrics
3. Look for:
   - HTTP request traces with automatic instrumentation
   - Custom spans for database operations
   - Structured logs with trace correlation
   - Custom metrics (request count, latency histogram)
   - Runtime metrics (goroutines, memory, GC)

## How to Add OpenTelemetry to an Existing Gin App on Cloud Run

To instrument your existing Gin application with OpenTelemetry for Cloud Run, follow these steps:

### 1. Install Required Packages

Add the following dependencies to your project:

```bash
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin@v0.55.0
go get go.opentelemetry.io/otel@v1.30.0
go get go.opentelemetry.io/otel/sdk@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@v1.30.0
go get go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp@v1.30.0
go get go.opentelemetry.io/contrib/instrumentation/runtime@v0.55.0
```

### 2. Create Telemetry Initialization File

**Copy the `telemetry.go` file from this repository into your project.** This file sets up:

- OTLP HTTP exporters for traces and metrics
- Cloud Run resource detection (service name, revision, region, project)
- Batch span processor with appropriate timeouts
- Periodic metric reader
- Runtime instrumentation for Go metrics

The telemetry file includes:

```go
package main

import (
	"context"
	"os"

	"go.opentelemetry.io/contrib/instrumentation/runtime"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// Create Cloud Run resource with semantic attributes
func createCloudRunResource(ctx context.Context) (*resource.Resource, error) {
	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = os.Getenv("K_SERVICE")
	}
	if serviceName == "" {
		serviceName = "go-cloud-run"
	}

	return resource.New(ctx,
		resource.WithFromEnv(),
		resource.WithTelemetrySDK(),
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.CloudProviderGCP,
			semconv.CloudPlatformGCPCloudRun,
			semconv.CloudRegion(os.Getenv("CLOUD_RUN_REGION")),
			semconv.CloudAccountID(os.Getenv("GOOGLE_CLOUD_PROJECT")),
			semconv.FaaSName(os.Getenv("K_SERVICE")),
			semconv.FaaSVersion(os.Getenv("K_REVISION")),
			semconv.ServiceInstanceID(os.Getenv("K_REVISION")),
		),
	)
}

// Initialize OpenTelemetry tracing and metrics
func initTelemetry() (*sdktrace.TracerProvider, *metric.MeterProvider) {
	ctx := context.Background()
	res, _ := createCloudRunResource(ctx)

	// Get endpoint and headers
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	endpoint = strings.TrimPrefix(endpoint, "https://")
	endpoint = strings.TrimPrefix(endpoint, "http://")

	headers := parseOTLPHeaders()

	// Initialize trace exporter
	traceExporter, _ := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(endpoint),
		otlptracehttp.WithHeaders(headers),
		otlptracehttp.WithURLPath("/v1/traces"),
	)

	// Create trace provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(traceExporter,
			sdktrace.WithBatchTimeout(5*time.Second),
			sdktrace.WithMaxExportBatchSize(512),
		),
	)
	otel.SetTracerProvider(tp)

	// Set up propagation
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// Initialize metric exporter
	metricExporter, _ := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(endpoint),
		otlpmetrichttp.WithHeaders(headers),
		otlpmetrichttp.WithURLPath("/v1/metrics"),
	)

	// Create meter provider
	mp := metric.NewMeterProvider(
		metric.WithResource(res),
		metric.WithReader(metric.NewPeriodicReader(metricExporter,
			metric.WithInterval(60*time.Second),
		)),
	)
	otel.SetMeterProvider(mp)

	// Enable runtime metrics
	runtime.Start(runtime.WithMinimumReadMemStatsInterval(time.Second))

	return tp, mp
}
```

### 3. Add OpenTelemetry Middleware to Gin

In your `main.go`, initialize telemetry and add the otelgin middleware:

```go
package main

import (
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
)

func main() {
	// Initialize telemetry
	tp, mp := initTelemetry()
	defer tp.Shutdown(context.Background())
	defer mp.Shutdown(context.Background())

	// Create Gin router
	r := gin.Default()

	// Add OpenTelemetry middleware
	r.Use(otelgin.Middleware("your-service-name"))

	// Your routes
	r.GET("/users", getUsers)

	r.Run(":8080")
}
```

### 4. Add Custom Spans

To create custom spans in your handlers:

```go
import (
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

var tracer = otel.Tracer("my-gin-app")

func getUsers(c *gin.Context) {
	ctx := c.Request.Context()

	// Create custom span
	ctx, span := tracer.Start(ctx, "fetch_users_from_database",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
		))
	defer span.End()

	// Your database logic here
	users := fetchUsersFromDB(ctx)

	c.JSON(200, users)
}
```

### 5. Add Structured Logging

For trace-correlated logs:

```go
import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"go.opentelemetry.io/otel/trace"
)

type LogEntry struct {
	Severity  string                 `json:"severity"`
	Message   string                 `json:"message"`
	Timestamp string                 `json:"timestamp"`
	Trace     string                 `json:"logging.googleapis.com/trace,omitempty"`
	SpanID    string                 `json:"logging.googleapis.com/spanId,omitempty"`
}

func structuredLog(ctx context.Context, level, message string) {
	entry := LogEntry{
		Severity:  level,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
	}

	// Add trace correlation
	span := trace.SpanFromContext(ctx)
	if span.SpanContext().IsValid() {
		projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
		if projectID != "" {
			entry.Trace = fmt.Sprintf("projects/%s/traces/%s", projectID, span.SpanContext().TraceID().String())
			entry.SpanID = span.SpanContext().SpanID().String()
		}
	}

	jsonBytes, _ := json.Marshal(entry)
	fmt.Println(string(jsonBytes))
}

// Use in handlers
func getUsers(c *gin.Context) {
	structuredLog(c.Request.Context(), "INFO", "Fetching all users")
	// ... your code
}
```

### 6. Set Environment Variables

Configure your Cloud Run service:

```bash
gcloud run services update YOUR_SERVICE_NAME \
  --set-env-vars "OTEL_SERVICE_NAME=your-service-name" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 7. Deploy and Verify

Deploy your instrumented application:

```bash
gcloud run deploy YOUR_SERVICE_NAME \
  --source . \
  --region us-central1
```

Generate traffic and verify traces, logs, and metrics appear in Last9.

---

**Tip:** For a complete working example, see the files in this repository:
- `telemetry.go` - Full OpenTelemetry SDK setup
- `main.go` - Gin app with structured logging and custom metrics
- `go.mod` - Dependencies

## Troubleshooting

### Cold Start Timeouts

**Symptom**: Spans not appearing in Last9

**Solution**: Ensure shutdown timeout is sufficient in `service.yaml`:

```yaml
spec:
  template:
    spec:
      timeoutSeconds: 300
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

Tips for managing Cloud Run costs:
- Use `--min-instances=0` to scale to zero during low traffic
- Set `--max-instances` to prevent runaway costs
- Monitor billable time via infrastructure metrics collector
- Right-size memory allocation (256Mi, 512Mi, 1Gi)
