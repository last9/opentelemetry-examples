package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"

	"github.com/last9/go-agent"
	"github.com/last9/go-agent/instrumentation/grpcgateway"
	pb "grpc-example/proto"

	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// server implements the Greeter service
type server struct {
	pb.UnimplementedGreeterServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	log.Printf("Received request: name=%s", in.Name)
	return &pb.HelloReply{Message: "Hello " + in.Name}, nil
}

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	// Start gRPC server on port 50051
	go startGrpcServer()

	// Start HTTP gateway on port 8080
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
func startHTTPGateway() error {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Create grpc-gateway ServeMux (handles gRPC-to-JSON transcoding)
	gwMux := runtime.NewServeMux()

	// Connect to gRPC server with go-agent client instrumentation
	opts := []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpcgateway.NewDialOption(), // Automatic OTel client tracing
	}

	conn, err := grpc.NewClient("localhost:50051", opts...)
	if err != nil {
		return fmt.Errorf("failed to dial gRPC server: %w", err)
	}
	defer conn.Close()

	// Register gRPC-gateway handlers
	if err := pb.RegisterGreeterHandler(ctx, gwMux, conn); err != nil {
		return fmt.Errorf("failed to register gateway: %w", err)
	}

	// Create standard library http.ServeMux
	httpMux := http.NewServeMux()

	// Mount grpc-gateway routes
	httpMux.Handle("/", gwMux)

	// Add a health check endpoint
	httpMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Wrap entire HTTP server with go-agent instrumentation
	handler := grpcgateway.WrapHTTPMux(httpMux, "grpc-gateway-http")

	// Start HTTP server
	log.Println("✓ HTTP gateway listening on :8080 (instrumented by go-agent)")
	log.Println("Try: curl -X POST http://localhost:8080/v1/greeter/hello -d '{\"name\":\"World\"}'")
	log.Println("Health check: curl http://localhost:8080/health")

	return http.ListenAndServe(":8080", handler)
}
