package main

import (
	"context"
	"log"
	"os"
	"time"

	agent "github.com/last9/go-agent"
	grpcagent "github.com/last9/go-agent/instrumentation/grpc"
	pb "grpc-example/proto"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	// Connect to gRPC server with go-agent (automatic client instrumentation)
	conn, err := grpc.NewClient(
		"localhost:" + func() string { if p := os.Getenv("GRPC_PORT"); p != "" { return p }; return "50051" }(),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpcagent.NewClientDialOption(), // Automatic OTel client tracing
	)
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()

	c := pb.NewGreeterClient(conn)

	name := "World"
	if len(os.Args) > 1 {
		name = os.Args[1]
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	r, err := c.SayHello(ctx, &pb.HelloRequest{Name: name})
	if err != nil {
		log.Fatalf("could not greet: %v", err)
	}
	log.Printf("✓ Greeting: %s", r.GetMessage())
}
