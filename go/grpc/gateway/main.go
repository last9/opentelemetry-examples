package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"

	instrumentation "grpc-example/instrumentation"
	pb "grpc-example/proto"

	"github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// server implements the Greeter service
type server struct {
	pb.UnimplementedGreeterServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	// Create a span for this method
	_, span := otel.Tracer("grpc-gateway-server").Start(ctx, "SayHello")
	defer span.End()

	log.Printf("Received request: name=%s", in.Name)
	return &pb.HelloReply{Message: "Hello " + in.Name}, nil
}

func main() {
	// Initialize OpenTelemetry tracer
	shutdown := instrumentation.InitTracer("grpc-gateway-example")
	defer shutdown(context.Background())

	// Start gRPC server on port 50051
	go startGrpcServer()

	// Give gRPC server time to start
	log.Println("Waiting for gRPC server to start...")
	// In production, use proper health checking
	// time.Sleep(time.Second)

	// Start HTTP gateway on port 8080
	if err := startHTTPGateway(); err != nil {
		log.Fatalf("Failed to start HTTP gateway: %v", err)
	}
}

// startGrpcServer starts the gRPC server with OpenTelemetry instrumentation
func startGrpcServer() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Failed to listen on gRPC port: %v", err)
	}

	// Create gRPC server with OTel interceptors
	grpcServer := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)

	// Register the Greeter service
	pb.RegisterGreeterServer(grpcServer, &server{})

	log.Printf("gRPC server listening at %v", lis.Addr())
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve gRPC: %v", err)
	}
}

// startHTTPGateway starts the grpc-gateway HTTP server with full instrumentation
func startHTTPGateway() error {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Create grpc-gateway ServeMux (handles gRPC-to-JSON transcoding)
	gwMux := runtime.NewServeMux()

	// Connect to gRPC server with OTel client instrumentation
	opts := []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
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

	// Wrap entire HTTP server with OTel instrumentation (outermost layer)
	handler := otelhttp.NewHandler(httpMux, "grpc-gateway-http")

	// Start HTTP server
	log.Println("HTTP gateway listening on :8080")
	log.Println("Try: curl -X POST http://localhost:8080/v1/greeter/hello -d '{\"name\":\"World\"}'")
	log.Println("Health check: curl http://localhost:8080/health")

	return http.ListenAndServe(":8080", handler)
}
