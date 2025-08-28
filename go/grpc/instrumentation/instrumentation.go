package instrumentation

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
)

// InitTracer initializes the OpenTelemetry tracer
func InitTracer(serviceName string) func(context.Context) error {
	// Set environment variables OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS
	// to the destination where you want to push traces.
	exporter, err := otlptracegrpc.New(context.Background())
	if err != nil {
		panic(err)
	}

	// exporter, err := otlptracegrpc.New(context.Background(),
	// 	otlptracegrpc.WithEndpoint(<last9_otlp_endpoint_without_https>),
	// 	otlptracegrpc.WithHeaders(map[string]string{
	// 		"Authorization":   "Basic <last9_auth_header>",
	// 	}),
	// )

	attr := resource.WithAttributes(
		semconv.DeploymentEnvironmentKey.String("production"), // You can change this value to "development" or "staging" or you can get the value from the environment variables
		semconv.ServiceNameKey.String(serviceName),
		// You can add more resource attributes here
	)

	resources, err := resource.New(context.Background(),
		resource.WithFromEnv(),
		resource.WithTelemetrySDK(),
		resource.WithProcess(),
		resource.WithOS(),
		resource.WithContainer(),
		resource.WithHost(),
		attr)

	if err != nil {
		panic(err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resources),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))

	return tp.Shutdown
}
