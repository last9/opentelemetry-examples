package last9

import (
	"context"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
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

	var tracerProviderOpts []sdktrace.TracerProviderOption

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

	tracerProviderOpts = append(tracerProviderOpts, sdktrace.WithResource(resources))
	tracerProviderOpts = append(tracerProviderOpts, sdktrace.WithBatcher(exporter))

	if os.Getenv("OTEL_CONSOLE_EXPORTER") == "true" {
		consoleExporter, err := stdouttrace.New(stdouttrace.WithPrettyPrint())
		if err == nil {
			tracerProviderOpts = append(tracerProviderOpts, sdktrace.WithBatcher(consoleExporter))
		}
	}

	tp := sdktrace.NewTracerProvider(tracerProviderOpts...)

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
