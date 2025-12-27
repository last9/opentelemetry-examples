package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httptrace"
	"os"

	// Last9 go-agent imports (drop-in replacements!)
	"github.com/last9/go-agent"
	"github.com/last9/go-agent/instrumentation/grpcgateway"
	"github.com/last9/go-agent/integrations/database"
	httpintegration "github.com/last9/go-agent/integrations/http"

	pb "grpc-gateway-example/proto"

	_ "github.com/lib/pq" // PostgreSQL driver
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// User represents a user in the database
type User struct {
	ID         int
	Name       string
	Email      string
	GreetCount int
}

// server implements the Greeter service with DB and external API integration
type server struct {
	pb.UnimplementedGreeterServer
	db         *sql.DB
	httpClient *http.Client
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	// Note: gRPC span is automatically created by go-agent, no need for manual span here
	log.Printf("Gateway received request: name=%s", in.Name)

	var greetCount int

	// Database operations (automatically instrumented by go-agent)
	if s.db != nil {
		// Check if user exists
		var userID int
		err := s.db.QueryRowContext(ctx, "SELECT id, greet_count FROM users WHERE name = $1", in.Name).Scan(&userID, &greetCount)

		if err != nil {
			// User doesn't exist, create new one
			email := fmt.Sprintf("%s@example.com", in.Name)
			err = s.db.QueryRowContext(ctx,
				"INSERT INTO users (name, email, greet_count) VALUES ($1, $2, 1) RETURNING id, greet_count",
				in.Name, email,
			).Scan(&userID, &greetCount)

			if err != nil {
				log.Printf("Error creating user: %v", err)
				greetCount = 1
			}
		} else {
			// User exists, increment count
			_, err = s.db.ExecContext(ctx, "UPDATE users SET greet_count = greet_count + 1 WHERE id = $1", userID)
			if err != nil {
				log.Printf("Error incrementing count: %v", err)
			}
			greetCount++
		}
	} else {
		greetCount = 1
	}

	// Simulate user location (based on name hash)
	locations := []string{"San Francisco", "New York", "London", "Tokyo", "Berlin", "Sydney"}
	weather := []string{"Sunny ☀️", "Partly Cloudy ⛅", "Cloudy ☁️", "Rainy 🌧️", "Snowy ❄️", "Windy 💨"}

	hash := 0
	for _, c := range in.Name {
		hash += int(c)
	}
	location := locations[hash%len(locations)]
	weatherCondition := weather[hash%len(weather)]

	// External API call for inspirational quote (automatically instrumented by go-agent)
	quote := "Have a great day!"
	author := "Anonymous"

	if s.httpClient != nil {
		// Create context with httptrace for proper span nesting
		ctx = httptrace.WithClientTrace(ctx, otelhttptrace.NewClientTrace(ctx))

		req, err := http.NewRequestWithContext(ctx, "GET", "https://api.quotable.io/random", nil)
		if err == nil {
			resp, err := s.httpClient.Do(req)
			if err == nil && resp != nil {
				defer resp.Body.Close()
				// Could parse JSON here, but skipping for simplicity
				quote = "Keep pushing forward!"
				author = "go-agent"
			}
		}
	}

	// Build rich response
	message := fmt.Sprintf("Hello %s from gRPC-Gateway! 👋 (powered by go-agent)\n", in.Name)
	message += fmt.Sprintf("You've been greeted %d times!\n", greetCount)
	message += fmt.Sprintf("Location: %s (%s)\n", location, weatherCondition)
	message += fmt.Sprintf("\nInspirational quote: \"%s\" - %s", quote, author)

	return &pb.HelloReply{Message: message}, nil
}

func main() {
	// 1. Initialize go-agent (ONE LINE!)
	// This automatically configures:
	//   - TracerProvider (with HTTP exporter)
	//   - MeterProvider (with gRPC exporter)
	//   - TextMapPropagator (for context propagation)
	//   - Resource attributes from environment
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized (all OpenTelemetry providers configured)")

	// 2. Database connection with automatic instrumentation
	var db *sql.DB
	var err error

	dsn := os.Getenv("DATABASE_URL")
	if dsn != "" {
		db, err = database.Open(database.Config{
			DriverName:   "postgres",
			DSN:          dsn,
			DatabaseName: "grpc_gateway",
		})
		if err != nil {
			log.Printf("Warning: Database connection failed: %v", err)
			log.Println("Continuing without database (greet counts won't persist)...")
			db = nil
		} else {
			defer db.Close()

			// Create schema
			if err := initSchema(db); err != nil {
				log.Printf("Warning: Failed to initialize schema: %v", err)
			}

			log.Println("✓ Database connected with automatic go-agent instrumentation")
		}
	} else {
		log.Println("DATABASE_URL not set, running without database")
	}

	// 3. HTTP client with automatic instrumentation
	httpClient := httpintegration.NewClient(&http.Client{})
	log.Println("✓ HTTP client configured with automatic go-agent instrumentation")

	log.Println("")
	log.Println("Starting Enhanced gRPC-Gateway with go-agent...")
	log.Println("Features:")
	log.Println("  ✓ gRPC server (auto-instrumented by go-agent)")
	log.Println("  ✓ HTTP gateway (auto-instrumented by go-agent)")
	if db != nil {
		log.Println("  ✓ PostgreSQL database (auto-instrumented by go-agent)")
	} else {
		log.Println("  ✗ PostgreSQL database (not connected)")
	}
	log.Println("  ✓ External API calls (auto-instrumented by go-agent)")
	log.Println("")
	log.Println("Benefits of go-agent:")
	log.Println("  • 87% less boilerplate code")
	log.Println("  • Standardized instrumentation patterns")
	log.Println("  • Drop-in replacements for common frameworks")
	log.Println("  • Centralized configuration")
	log.Println("")

	// Start gRPC server in background
	go startGrpcServer(db, httpClient)

	// Start HTTP gateway
	if err := startHTTPGateway(); err != nil {
		log.Fatalf("Failed to start HTTP gateway: %v", err)
	}
}

// startGrpcServer starts the gRPC server using go-agent
func startGrpcServer(db *sql.DB, httpClient *http.Client) {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Failed to listen on gRPC port: %v", err)
	}

	// Create gRPC server with go-agent (automatic instrumentation!)
	grpcServer := grpcgateway.NewGrpcServer()

	// Register the Greeter service
	pb.RegisterGreeterServer(grpcServer, &server{
		db:         db,
		httpClient: httpClient,
	})

	log.Printf("✓ gRPC server listening at %v (instrumented by go-agent)", lis.Addr())
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve gRPC: %v", err)
	}
}

// startHTTPGateway starts the grpc-gateway HTTP server using go-agent
func startHTTPGateway() error {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Create grpc-gateway ServeMux with go-agent
	gwMux := grpcgateway.NewGatewayMux()

	// Connect to gRPC server with go-agent (automatic client instrumentation!)
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
	if err := pb.RegisterGreeterHandler(ctx, gwMux, conn); err != nil {
		return fmt.Errorf("failed to register gateway: %w", err)
	}

	// Create standard library http.ServeMux
	httpMux := http.NewServeMux()

	// Mount grpc-gateway routes
	httpMux.Handle("/", gwMux)

	// Add health check endpoint
	httpMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Wrap entire HTTP server with go-agent (automatic instrumentation!)
	handler := grpcgateway.WrapHTTPMux(httpMux, "grpc-gateway-http")

	// Start HTTP server
	log.Println("✓ HTTP gateway listening on :8080 (instrumented by go-agent)")
	log.Println("")
	log.Println("Try these commands:")
	log.Println("  curl -X POST http://localhost:8080/v1/greeter/hello -d '{\"name\":\"World\"}'")
	log.Println("  curl http://localhost:8080/health")
	log.Println("")
	log.Println("Full trace includes:")
	log.Println("  → HTTP request (go-agent)")
	log.Println("  → gRPC call (go-agent)")
	log.Println("  → Database queries (go-agent)")
	log.Println("  → External API calls (go-agent)")
	log.Println("")

	return http.ListenAndServe(":8080", handler)
}

// initSchema creates the database schema
func initSchema(db *sql.DB) error {
	ctx := context.Background()

	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			name VARCHAR(255) NOT NULL,
			email VARCHAR(255) UNIQUE NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			greet_count INTEGER DEFAULT 0
		);
		CREATE INDEX IF NOT EXISTS idx_users_name ON users(name);
		CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
	`)

	if err != nil {
		return fmt.Errorf("failed to create schema: %w", err)
	}

	log.Println("✓ Database schema initialized")
	return nil
}
