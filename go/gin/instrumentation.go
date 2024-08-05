package main

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

type Instrumentation struct {
	TracerProvider *sdktrace.TracerProvider
	Tracer         trace.Tracer
}

func initTracerProvider() *sdktrace.TracerProvider {
	exporter, err := otlptracehttp.New(context.Background())

	if err != nil {
		panic(err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
		sdktrace.WithBatcher(exporter),
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
