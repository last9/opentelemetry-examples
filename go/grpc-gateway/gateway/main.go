package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"

	"github.com/last9/go-agent"
	"github.com/last9/go-agent/instrumentation/grpcgateway"
	pb "grpc-gateway-example/proto"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// server implements the Greeter service
type server struct {
	pb.UnimplementedGreeterServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	log.Printf("Gateway received request: name=%s", in.Name)
	return &pb.HelloReply{Message: "Hello " + in.Name + " from gRPC-Gateway!"}, nil
}

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")
	log.Println("Starting gRPC-Gateway example...")

	// Start gRPC server in background
	go startGrpcServer()

	// Start HTTP gateway
	if err := startHTTPGateway(); err != nil {
		log.Fatalf("Failed to start HTTP gateway: %v", err)
	}
}

// startGrpcServer starts the gRPC server with go-agent instrumentation
func startGrpcServer() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Failed to listen on gRPC port: %v", err)
	}

	// Create gRPC server with go-agent (automatic instrumentation)
	grpcServer := grpcgateway.NewGrpcServer()

	// Register the Greeter service
	pb.RegisterGreeterServer(grpcServer, &server{})

	log.Printf("✓ gRPC server listening at %v (instrumented by go-agent)", lis.Addr())
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve gRPC: %v", err)
	}
}

// startHTTPGateway starts the grpc-gateway HTTP server with go-agent instrumentation
// This demonstrates the complete stack: HTTP -> grpc-gateway -> gRPC
func startHTTPGateway() error {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Create grpc-gateway ServeMux with go-agent
	gwMux := grpcgateway.NewGatewayMux()

	// Connect to gRPC server with go-agent (automatic client instrumentation)
	opts := []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpcgateway.NewDialOption(), // Automatic OTel instrumentation
	}

	conn, err := grpc.NewClient("localhost:50051", opts...)
	if err != nil {
		return fmt.Errorf("failed to dial gRPC server: %w", err)
	}
	defer conn.Close()

	// Register gRPC-gateway handlers
	// This maps HTTP routes to gRPC methods based on proto annotations
	if err := pb.RegisterGreeterHandler(ctx, gwMux, conn); err != nil {
		return fmt.Errorf("failed to register gateway: %w", err)
	}

	// Create standard library http.ServeMux (outer HTTP layer)
	httpMux := http.NewServeMux()

	// Mount grpc-gateway routes under /
	httpMux.Handle("/", gwMux)

	// Add additional HTTP-only routes
	httpMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Wrap entire HTTP server with go-agent (automatic instrumentation)
	handler := grpcgateway.WrapHTTPMux(httpMux, "grpc-gateway-http")

	// Start HTTP server
	log.Println("✓ HTTP gateway listening on :8080 (instrumented by go-agent)")
	log.Println("")
	log.Println("Try these commands:")
	log.Println("  curl -X POST http://localhost:8080/v1/greeter/hello -d '{\"name\":\"World\"}'")
	log.Println("  curl http://localhost:8080/health")
	log.Println("")

	return http.ListenAndServe(":8080", handler)
}
