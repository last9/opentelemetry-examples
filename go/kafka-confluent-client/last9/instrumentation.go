package last9

import (
	"context"
	"fmt"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

type Instrumentation struct {
	TracerProvider *sdktrace.TracerProvider
	Tracer         trace.Tracer
}

func InitMetrics() (*metric.MeterProvider, error) {
	// Set environment variables OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS
	// to the destination where you want to push traces.
	exporter, err := otlpmetricgrpc.New(context.Background())
	if err != nil {
		fmt.Println("Error creating metrics exporter:", err)
		return nil, err
	}

	// exporter, err := otlptracegrpc.New(context.Background(),
	// 	otlptracegrpc.WithEndpoint(<last9_otlp_endpoint_without_https>),
	// 	otlptracegrpc.WithHeaders(map[string]string{
	// 		"Authorization":   "Basic <last9_auth_header>",
	// 	}),
	// )

	attr := resource.WithAttributes(
		semconv.DeploymentEnvironmentKey.String("production"), // You can change this value to "development" or "staging" or you can get the value from the environment variables
		// You can add more attributes here
		semconv.ServiceNameKey.String("gin-server"),
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
		return nil, err
	}

	// Set up the meter provider with the exporter and resource and a periodic reader that flushes every minute
	mp := metric.NewMeterProvider(metric.WithResource(resources),
		metric.WithReader(metric.NewPeriodicReader(exporter, metric.WithInterval(1*time.Minute))))
	return mp, nil
}

func initTracerProvider() *sdktrace.TracerProvider {
	exporter, err := otlptracehttp.New(context.Background())

	// You can also set the endpoint and authorization header inline as follows.

	// exporter, err := otlptracehttp.New(context.Background(),
	// 	otlptracehttp.WithEndpoint("otlp.last9.io"),
	// 	otlptracehttp.WithHeaders(map[string]string{
	// 		"Authorization":   "Basic <auth_header>",
	// 	}),
	// )
	if err != nil {
		panic(err)
	}

	attr := resource.WithAttributes(
		semconv.DeploymentEnvironmentKey.String("production"), // You can change this value to "development" or "staging" or you can get the value from the environment variables
		// You can add more attributes here
		semconv.ServiceNameKey.String("gin-server"),
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

	return tp
}

func NewInstrumentation() *Instrumentation {
	tp := initTracerProvider()

	return &Instrumentation{
		TracerProvider: tp,
		Tracer:         tp.Tracer("gin-server"),
	}
}
