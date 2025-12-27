package main

import (
	"context"
	"log"
	"net"

	"github.com/last9/go-agent"
	"github.com/last9/go-agent/instrumentation/grpcgateway"
	pb "grpc-gateway-example/proto"
)

type server struct {
	pb.UnimplementedGreeterServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	log.Printf("gRPC Server received: name=%s", in.Name)
	return &pb.HelloReply{Message: "Hello " + in.Name}, nil
}

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	// Create gRPC server with go-agent (automatic instrumentation)
	s := grpcgateway.NewGrpcServer()

	pb.RegisterGreeterServer(s, &server{})
	log.Printf("✓ gRPC server listening at %v (instrumented by go-agent)", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
