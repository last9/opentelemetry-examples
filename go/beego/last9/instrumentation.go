package last9

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

type Instrumentation struct {
	TracerProvider *sdktrace.TracerProvider
	Tracer         trace.Tracer
}

func initTracerProvider(serviceName string) *sdktrace.TracerProvider {
	exporter, err := otlptracehttp.New(context.Background())

	if err != nil {
		panic(err)
	}

	attr := resource.WithAttributes(
		semconv.DeploymentEnvironmentKey.String("production"),
		semconv.ServiceNameKey.String(serviceName),
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

func NewInstrumentation(serviceName string) *Instrumentation {
	tp := initTracerProvider(serviceName)

	return &Instrumentation{
		TracerProvider: tp,
		Tracer:         tp.Tracer(serviceName),
	}
}
