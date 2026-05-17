package main

import (
	"context"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func deltaTemporality(_ sdkmetric.InstrumentKind) metricdata.Temporality {
	return metricdata.DeltaTemporality
}

func cumulativeTemporality(_ sdkmetric.InstrumentKind) metricdata.Temporality {
	return metricdata.CumulativeTemporality
}

func newMeterProvider(ctx context.Context, endpoint string, temporality func(sdkmetric.InstrumentKind) metricdata.Temporality, svcName string) (*sdkmetric.MeterProvider, error) {
	exp, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(endpoint),
		otlpmetrichttp.WithInsecure(),
		otlpmetrichttp.WithTemporalitySelector(temporality),
	)
	if err != nil {
		return nil, err
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(svcName),
			semconv.ServiceVersion("1.0.0"),
		),
	)
	if err != nil {
		return nil, err
	}

	return sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(
			sdkmetric.NewPeriodicReader(exp, sdkmetric.WithInterval(5*time.Second)),
		),
		sdkmetric.WithResource(res),
	), nil
}

func main() {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "localhost:4318"
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Provider 1: delta temporality — simulates SDK that sends deltas (e.g. Golang default for some instruments)
	deltaMp, err := newMeterProvider(ctx, endpoint, deltaTemporality, "demo-delta")
	if err != nil {
		log.Fatalf("delta provider: %v", err)
	}
	defer deltaMp.Shutdown(context.Background())

	// Provider 2: cumulative temporality — simulates SDK that sends cumulative (e.g. Claude Code, Java default)
	cumulativeMp, err := newMeterProvider(ctx, endpoint, cumulativeTemporality, "demo-cumulative")
	if err != nil {
		log.Fatalf("cumulative provider: %v", err)
	}
	defer cumulativeMp.Shutdown(context.Background())

	deltaCounter, err := deltaMp.Meter("demo").Int64Counter(
		"demo_requests_delta_total",
		metric.WithDescription("Request counter with DELTA temporality"),
	)
	if err != nil {
		log.Fatalf("delta counter: %v", err)
	}

	cumulativeCounter, err := cumulativeMp.Meter("demo").Int64Counter(
		"demo_requests_cumulative_total",
		metric.WithDescription("Request counter with CUMULATIVE temporality"),
	)
	if err != nil {
		log.Fatalf("cumulative counter: %v", err)
	}

	log.Printf("sending to %s — delta + cumulative, every 2s", endpoint)

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("shutting down")
			return
		case <-ticker.C:
			inc := int64(rand.Intn(10) + 1)
			deltaCounter.Add(ctx, inc)
			cumulativeCounter.Add(ctx, inc)
			log.Printf("added %d to both counters", inc)
		}
	}
}
