package main

import (
	"context"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

// parseOTLPHeaders parses headers from environment variable format
// Format: "key1=value1,key2=value2"
func parseOTLPHeaders() map[string]string {
	headers := make(map[string]string)
	headersStr := os.Getenv("OTEL_EXPORTER_OTLP_HEADERS")

	if headersStr == "" {
		return headers
	}

	pairs := strings.Split(headersStr, ",")
	for _, pair := range pairs {
		parts := strings.SplitN(pair, "=", 2)
		if len(parts) == 2 {
			headers[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}

	return headers
}

// createCloudRunResource creates a resource with Cloud Run-specific attributes
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
			semconv.ServiceVersion(getEnvOrDefault("SERVICE_VERSION", "1.0.0")),
			semconv.DeploymentEnvironment(getEnvOrDefault("DEPLOYMENT_ENVIRONMENT", "production")),
			// Cloud Run specific attributes
			semconv.CloudProviderGCP,
			semconv.CloudPlatformGCPCloudRun,
			semconv.CloudRegion(getEnvOrDefault("CLOUD_RUN_REGION", getEnvOrDefault("GOOGLE_CLOUD_REGION", "unknown"))),
			semconv.CloudAccountID(getEnvOrDefault("GOOGLE_CLOUD_PROJECT", "unknown")),
			// FaaS attributes
			semconv.FaaSName(getEnvOrDefault("K_SERVICE", serviceName)),
			semconv.FaaSVersion(getEnvOrDefault("K_REVISION", "unknown")),
			semconv.FaaSInstance(getEnvOrDefault("K_REVISION", "unknown")),
			// Service instance
			semconv.ServiceInstanceID(getEnvOrDefault("K_REVISION", "local")),
		),
	)
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// initTelemetry initializes OpenTelemetry tracing and metrics
func initTelemetry() (*sdktrace.TracerProvider, *metric.MeterProvider) {
	ctx := context.Background()

	// Create resource
	res, err := createCloudRunResource(ctx)
	if err != nil {
		panic(err)
	}

	// Get endpoint
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "https://otlp.last9.io"
	}
	// Remove protocol prefix for HTTP exporter
	endpoint = strings.TrimPrefix(endpoint, "https://")
	endpoint = strings.TrimPrefix(endpoint, "http://")

	headers := parseOTLPHeaders()

	// Initialize trace exporter
	traceExporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(endpoint),
		otlptracehttp.WithHeaders(headers),
		otlptracehttp.WithURLPath("/v1/traces"),
	)
	if err != nil {
		panic(err)
	}

	// Create trace provider with batch processor
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
	metricExporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(endpoint),
		otlpmetrichttp.WithHeaders(headers),
		otlpmetrichttp.WithURLPath("/v1/metrics"),
	)
	if err != nil {
		panic(err)
	}

	// Create meter provider
	mp := metric.NewMeterProvider(
		metric.WithResource(res),
		metric.WithReader(metric.NewPeriodicReader(metricExporter,
			metric.WithInterval(60*time.Second),
		)),
	)
	otel.SetMeterProvider(mp)

	return tp, mp
}
