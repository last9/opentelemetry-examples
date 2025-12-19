package main

import (
	"context"
	"log"
	"net"

	instrumentation "grpc-gateway-example/instrumentation"
	pb "grpc-gateway-example/proto"

	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/otel"
	"google.golang.org/grpc"
)

type server struct {
	pb.UnimplementedGreeterServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	// Create a span for this method
	_, span := otel.Tracer("grpc-server").Start(ctx, "SayHello")
	defer span.End()

	log.Printf("gRPC Server received: name=%s", in.Name)
	return &pb.HelloReply{Message: "Hello " + in.Name}, nil
}

func main() {
	// Initialize the tracer
	shutdown := instrumentation.InitTracer("grpc-gateway-server")
	defer shutdown(context.Background())

	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	// Create gRPC server with OpenTelemetry instrumentation
	s := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)

	pb.RegisterGreeterServer(s, &server{})
	log.Printf("gRPC server listening at %v", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
