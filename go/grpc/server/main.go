package main

import (
	"context"
	"log"
	"net"
	"os"

	agent "github.com/last9/go-agent"
	grpcagent "github.com/last9/go-agent/instrumentation/grpc"
	pb "grpc-example/proto"
)

type server struct {
	pb.UnimplementedGreeterServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	return &pb.HelloReply{Message: "Hello " + in.Name}, nil
}

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	port := ":50051"
	if p := os.Getenv("GRPC_PORT"); p != "" {
		port = ":" + p
	}
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	// Create gRPC server with go-agent (automatic instrumentation)
	s := grpcagent.NewServer()

	pb.RegisterGreeterServer(s, &server{})
	log.Printf("✓ gRPC server listening at %v (instrumented by go-agent)", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
