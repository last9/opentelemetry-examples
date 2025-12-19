package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"time"

	instrumentation "grpc-gateway-example/instrumentation"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
)

type HelloRequest struct {
	Name string `json:"name"`
}

type HelloReply struct {
	Message string `json:"message"`
}

var names = []string{
	"Alice", "Bob", "Charlie", "Diana", "Eve",
	"Frank", "Grace", "Henry", "Ivy", "Jack",
	"Kate", "Leo", "Maya", "Nina", "Oscar",
	"Paul", "Quinn", "Ruby", "Sam", "Tina",
	"Uma", "Victor", "Wendy", "Xavier", "Yara", "Zoe",
}

func main() {
	// Initialize the tracer with a different service name
	shutdown := instrumentation.InitTracer("grpc-gateway-traffic-generator")
	defer shutdown(context.Background())

	// Create HTTP client with OpenTelemetry instrumentation
	client := &http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
		Timeout:   5 * time.Second,
	}

	const totalRequests = 100
	successCount := 0
	failureCount := 0

	log.Printf("🚀 Starting traffic generator...")
	log.Printf("   Target: http://localhost:8080/v1/greeter/hello")
	log.Printf("   Total requests: %d", totalRequests)
	log.Println("")

	startTime := time.Now()

	for i := 0; i < totalRequests; i++ {
		// Pick a random name
		name := names[rand.Intn(len(names))]

		// Create a new context with trace for each request
		ctx := context.Background()
		tracer := otel.Tracer("traffic-generator")
		ctx, span := tracer.Start(ctx, "generate-traffic")
		span.SetAttributes(
			attribute.String("request.name", name),
			attribute.Int("request.number", i+1),
		)

		// Send request
		if err := sendRequest(ctx, client, name, i+1, totalRequests); err != nil {
			log.Printf("  ✗ [%d/%d] Request failed: %v", i+1, totalRequests, err)
			failureCount++
			span.SetAttributes(attribute.Bool("request.success", false))
		} else {
			successCount++
			span.SetAttributes(attribute.Bool("request.success", true))
		}

		span.End()

		// Random delay between requests (100ms to 1s)
		delay := time.Duration(100+rand.Intn(900)) * time.Millisecond
		time.Sleep(delay)
	}

	duration := time.Since(startTime)

	log.Println("")
	log.Println("✅ Traffic generation complete!")
	log.Printf("   Duration: %v", duration)
	log.Printf("   Successful: %d/%d", successCount, totalRequests)
	log.Printf("   Failed: %d/%d", failureCount, totalRequests)
	log.Printf("   Avg time per request: %v", duration/time.Duration(totalRequests))
	log.Println("")
	log.Println("🔍 View traces in Last9 dashboard:")
	log.Println("   https://app.last9.io")
	log.Println("   Service name: grpc-gateway-traffic-generator")
	log.Println("   Downstream service: grpc-gateway-demo")

	// Give time for final traces to be exported
	time.Sleep(2 * time.Second)
}

func sendRequest(ctx context.Context, client *http.Client, name string, reqNum, total int) error {
	// Prepare request body
	reqBody := HelloRequest{Name: name}
	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP request with context
	req, err := http.NewRequestWithContext(
		ctx,
		"POST",
		"http://localhost:8080/v1/greeter/hello",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Send request
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response: %w", err)
	}

	// Parse response
	var reply HelloReply
	if err := json.Unmarshal(body, &reply); err != nil {
		return fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Log success
	log.Printf("  ✓ [%d/%d] %s → %s", reqNum, total, name, reply.Message)

	return nil
}
