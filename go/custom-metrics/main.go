package main

import (
	"context"
	"log"
	"math/rand"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	otelmetric "go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func initMeterProvider(ctx context.Context) (*metric.MeterProvider, error) {
	exporter, err := otlpmetrichttp.New(ctx)
	if err != nil {
		return nil, err
	}

	res, err := resource.New(ctx,
		resource.WithFromEnv(),
		resource.WithAttributes(
			semconv.ServiceNameKey.String("custom-metrics-example"),
			semconv.DeploymentEnvironmentKey.String("development"),
		),
	)
	if err != nil {
		return nil, err
	}

	mp := metric.NewMeterProvider(
		metric.WithResource(res),
		metric.WithReader(metric.NewPeriodicReader(exporter,
			metric.WithInterval(15*time.Second),
		)),
	)
	otel.SetMeterProvider(mp)
	return mp, nil
}

func main() {
	ctx := context.Background()

	mp, err := initMeterProvider(ctx)
	if err != nil {
		log.Fatalf("init meter provider: %v", err)
	}
	defer func() {
		if err := mp.ForceFlush(ctx); err != nil {
			log.Printf("flush error: %v", err)
		}
		if err := mp.Shutdown(ctx); err != nil {
			log.Printf("shutdown error: %v", err)
		}
	}()

	meter := otel.Meter("custom-metrics-example")

	// Counter: tracks how many times an event occurred
	resolutionCounter, err := meter.Int64Counter(
		"subscription.upgrade.notification.resolution",
		otelmetric.WithDescription("Count of subscription upgrade notification resolutions"),
	)
	if err != nil {
		log.Fatalf("create counter: %v", err)
	}

	// Histogram: tracks distribution of a value (e.g. latency)
	requestDuration, err := meter.Float64Histogram(
		"request.duration",
		otelmetric.WithDescription("Request duration in seconds"),
		otelmetric.WithUnit("s"),
	)
	if err != nil {
		log.Fatalf("create histogram: %v", err)
	}

	// Gauge: tracks a current value that can go up or down
	queueDepth, err := meter.Int64Gauge(
		"queue.depth",
		otelmetric.WithDescription("Current number of items in the queue"),
	)
	if err != nil {
		log.Fatalf("create gauge: %v", err)
	}

	statuses := []string{"success", "failure", "timeout"}
	reasons := []string{"completed", "rejected", "expired"}
	products := []string{"premium", "basic", "trial"}

	log.Println("emitting metrics every 5s, press Ctrl+C to stop")

	for i := 0; i < 10; i++ {
		status := statuses[rand.Intn(len(statuses))]
		reason := reasons[rand.Intn(len(reasons))]
		product := products[rand.Intn(len(products))]

		// IMPORTANT: never pass empty string as attribute value.
		// Last9 follows the Prometheus data model: labels with empty values
		// silently — the metric is recorded but that label dimension is absent.
		// Use a sentinel like "unknown" if the value may be empty.
		if status == "" {
			status = "unknown"
		}
		if reason == "" {
			reason = "unknown"
		}
		if product == "" {
			product = "unknown"
		}

		resolutionCounter.Add(ctx, 1, otelmetric.WithAttributes(
			attribute.String("status", status),
			attribute.String("reason", reason),
			attribute.String("product_type", product),
		))

		duration := 0.1 + rand.Float64()*0.9
		requestDuration.Record(ctx, duration, otelmetric.WithAttributes(
			attribute.String("method", "POST"),
			attribute.String("status_code", "200"),
			attribute.String("product_type", product),
		))

		depth := int64(rand.Intn(100))
		queueDepth.Record(ctx, depth, otelmetric.WithAttributes(
			attribute.String("queue_name", "notifications"),
		))

		log.Printf("recorded: status=%s reason=%s product_type=%s duration=%.3fs queue_depth=%d",
			status, reason, product, duration, depth)

		time.Sleep(5 * time.Second)
	}

	log.Println("done — metrics will appear in Last9 as:")
	log.Println("  subscription_upgrade_notification_resolution_total")
	log.Println("  request_duration_seconds_bucket / _count / _sum")
	log.Println("  queue_depth")
}
