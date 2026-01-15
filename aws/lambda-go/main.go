package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-lambda-go/otellambda"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// MyEvent represents the input event structure
type MyEvent struct {
	Name    string `json:"name"`
	Message string `json:"message"`
}

// MyResponse represents the output response structure
type MyResponse struct {
	StatusCode int    `json:"statusCode"`
	Body       string `json:"body"`
}

// HandleRequest is your Lambda function handler
func HandleRequest(ctx context.Context, event MyEvent) (MyResponse, error) {
	log.Printf("Received event: Name=%s, Message=%s", event.Name, event.Message)

	// Your business logic here
	responseBody := fmt.Sprintf("Hello %s! Your message was: %s", event.Name, event.Message)

	response := MyResponse{
		StatusCode: 200,
		Body:       responseBody,
	}

	return response, nil
}

func initTracer() (*sdktrace.TracerProvider, error) {
	// Create OTLP trace exporter that sends to localhost:4317 (ADOT Collector)
	ctx := context.Background()
	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint("localhost:4317"),
		otlptracegrpc.WithInsecure(),
		otlptracegrpc.WithDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP trace exporter: %w", err)
	}

	// Create resource with service name from environment variable
	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "go-lambda-otel-example" // fallback default
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Create tracer provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)

	// Set as global tracer provider
	otel.SetTracerProvider(tp)

	return tp, nil
}

func main() {
	// Initialize tracer
	tp, err := initTracer()
	if err != nil {
		log.Fatalf("Failed to initialize tracer: %v", err)
	}

	// Ensure tracer is flushed on shutdown
	defer func() {
		if err := tp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Wrap the handler with OpenTelemetry instrumentation
	// The Flusher ensures traces are sent before Lambda freezes
	lambda.Start(otellambda.InstrumentHandler(HandleRequest, otellambda.WithFlusher(tp)))
}
