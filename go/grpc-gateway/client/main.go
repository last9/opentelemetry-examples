package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	instrumentation "grpc-gateway-example/instrumentation"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

type HelloRequest struct {
	Name string `json:"name"`
}

type HelloReply struct {
	Message string `json:"message"`
}

func main() {
	// Initialize the tracer
	shutdown := instrumentation.InitTracer("grpc-gateway-client")
	defer shutdown(context.Background())

	// Get name from command line args or use default
	name := "World"
	if len(os.Args) > 1 {
		name = os.Args[1]
	}

	// Create HTTP client with OpenTelemetry instrumentation
	client := &http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}

	// Prepare request body
	reqBody := HelloRequest{Name: name}
	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		log.Fatalf("Failed to marshal request: %v", err)
	}

	// Make HTTP POST request to grpc-gateway
	resp, err := client.Post(
		"http://localhost:8080/v1/greeter/hello",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		log.Fatalf("Failed to call API: %v", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("Failed to read response: %v", err)
	}

	// Parse response
	var reply HelloReply
	if err := json.Unmarshal(body, &reply); err != nil {
		log.Fatalf("Failed to unmarshal response: %v", err)
	}

	// Print result
	fmt.Printf("Response: %s\n", reply.Message)
	log.Printf("Successfully called gRPC service via HTTP gateway")
}
