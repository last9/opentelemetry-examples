package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	// Import the Last9 go-agent packages (drop-in replacements)
	"github.com/last9/go-agent"
	"github.com/last9/go-agent/instrumentation/grpcgateway"
	"github.com/last9/go-agent/integrations/database"
	httpagent "github.com/last9/go-agent/integrations/http"
	redisagent "github.com/last9/go-agent/integrations/redis"

	pb "grpc-gateway-example/proto"

	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Tracer for creating manual spans
var tracer = otel.Tracer("grpc-gateway-service")

// Dependencies holds all instrumented clients
type Dependencies struct {
	DB         *sql.DB
	Redis      *redis.Client
	HTTPClient *http.Client
}

type server struct {
	pb.UnimplementedGreeterServer
	deps *Dependencies
}

// ExternalAPIResponse represents a response from httpbin
type ExternalAPIResponse struct {
	Origin  string            `json:"origin"`
	Headers map[string]string `json:"headers"`
	URL     string            `json:"url"`
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	// Create a child span for the business logic
	// Parent: gRPC server span (automatically created by grpcgateway.NewGrpcServer)
	ctx, span := tracer.Start(ctx, "SayHello.ProcessRequest",
		trace.WithAttributes(
			attribute.String("user.name", in.Name),
		),
	)
	defer span.End()

	log.Printf("Gateway received request: name=%s", in.Name)

	var messageParts []string
	messageParts = append(messageParts, fmt.Sprintf("Hello %s!", in.Name))

	// 1. Redis operations - child span ensures proper hierarchy
	if s.deps.Redis != nil {
		redisResult := s.handleRedisOperations(ctx, in.Name)
		messageParts = append(messageParts, redisResult...)
	}

	// 2. Database operations - child span ensures proper hierarchy
	if s.deps.DB != nil {
		dbResult := s.handleDatabaseOperations(ctx)
		messageParts = append(messageParts, dbResult...)
	}

	// 3. External HTTP call - child span ensures proper hierarchy
	if s.deps.HTTPClient != nil {
		httpResult := s.handleExternalAPICall(ctx, in.Name)
		messageParts = append(messageParts, httpResult...)
	}

	// Build response message
	message := ""
	for i, part := range messageParts {
		if i > 0 {
			message += " | "
		}
		message += part
	}

	span.SetAttributes(attribute.String("response.message", message))
	return &pb.HelloReply{Message: message}, nil
}

// handleRedisOperations performs Redis operations within a parent span
// Span hierarchy: SayHello.ProcessRequest -> redis.operations -> individual Redis commands
func (s *server) handleRedisOperations(ctx context.Context, name string) []string {
	ctx, span := tracer.Start(ctx, "redis.operations",
		trace.WithAttributes(
			attribute.String("cache.key_prefix", "greeting"),
			attribute.String("user.name", name),
		),
	)
	defer span.End()

	var results []string
	cacheKey := fmt.Sprintf("greeting:%s", name)

	// Redis GET - the redisagent automatically creates a child span
	cached, err := s.deps.Redis.Get(ctx, cacheKey).Result()
	if err == nil {
		log.Printf("  -> Cache HIT for %s", name)
		span.SetAttributes(attribute.Bool("cache.hit", true))
		results = append(results, fmt.Sprintf("(cached: %s)", cached))
	} else if err == redis.Nil {
		log.Printf("  -> Cache MISS for %s, storing...", name)
		span.SetAttributes(attribute.Bool("cache.hit", false))

		// Redis SET - child span auto-created
		s.deps.Redis.Set(ctx, cacheKey, time.Now().Format(time.RFC3339), 5*time.Minute)
		results = append(results, "(freshly cached)")
	} else {
		span.RecordError(err)
		span.SetStatus(codes.Error, "Redis GET failed")
	}

	// Redis INCR - child span auto-created
	visits, err := s.deps.Redis.Incr(ctx, fmt.Sprintf("visits:%s", name)).Result()
	if err == nil {
		span.SetAttributes(attribute.Int64("user.visit_count", visits))
		results = append(results, fmt.Sprintf("Visit #%d", visits))
	}

	return results
}

// handleDatabaseOperations performs DB queries within a parent span
// Span hierarchy: SayHello.ProcessRequest -> database.operations -> individual SQL queries
func (s *server) handleDatabaseOperations(ctx context.Context) []string {
	ctx, span := tracer.Start(ctx, "database.operations",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
		),
	)
	defer span.End()

	var results []string

	// Query 1: Get current time - database package auto-creates child span
	var dbTime string
	err := s.deps.DB.QueryRowContext(ctx, "SELECT NOW()::text").Scan(&dbTime)
	if err == nil {
		log.Printf("  -> DB query successful: %s", dbTime)
		span.SetAttributes(attribute.String("db.server_time", dbTime))
		results = append(results, fmt.Sprintf("DB time: %s", dbTime))
	} else {
		log.Printf("  -> DB query failed: %v", err)
		span.RecordError(err)
	}

	// Query 2: Count tables - database package auto-creates child span
	var tableCount int
	err = s.deps.DB.QueryRowContext(ctx,
		"SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public'").Scan(&tableCount)
	if err == nil {
		span.SetAttributes(attribute.Int("db.table_count", tableCount))
		results = append(results, fmt.Sprintf("Tables: %d", tableCount))
	}

	return results
}

// handleExternalAPICall makes an external HTTP call within a parent span
// Span hierarchy: SayHello.ProcessRequest -> external.api.call -> HTTP client span
func (s *server) handleExternalAPICall(ctx context.Context, name string) []string {
	ctx, span := tracer.Start(ctx, "external.api.call",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("http.url", "https://httpbin.org/get"),
			attribute.String("external.service", "httpbin"),
			attribute.String("request.name", name),
		),
	)
	defer span.End()

	var results []string

	apiResp, err := fetchExternalAPI(ctx, s.deps.HTTPClient, name)
	if err == nil {
		log.Printf("  -> External API call successful: origin=%s", apiResp.Origin)
		span.SetAttributes(
			attribute.String("http.response.origin", apiResp.Origin),
			attribute.Int("http.status_code", 200),
		)
		span.SetStatus(codes.Ok, "API call successful")
		results = append(results, fmt.Sprintf("From IP: %s", apiResp.Origin))
	} else {
		log.Printf("  -> External API call failed: %v", err)
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}

	return results
}

// fetchExternalAPI makes an instrumented HTTP call to httpbin
// The httpagent.NewClient automatically creates spans for HTTP requests
func fetchExternalAPI(ctx context.Context, client *http.Client, name string) (*ExternalAPIResponse, error) {
	url := fmt.Sprintf("https://httpbin.org/get?name=%s", name)

	// Create request WITH context - this is critical for span propagation
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Custom-Header", "Last9-Go-Agent-Test")

	// The instrumented client will create a child span and inject trace headers
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var apiResp ExternalAPIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}

	return &apiResp, nil
}

func main() {
	// 1. Initialize the go-agent (ONE LINE!)
	// This automatically sets up all OpenTelemetry providers
	agent.Start()
	defer agent.Shutdown()

	log.Println("============================================================")
	log.Println("  gRPC-Gateway with Last9 go-agent - Full Instrumentation")
	log.Println("============================================================")
	log.Println("")
	log.Println("[Last9 Agent] Initialized successfully")

	deps := &Dependencies{}

	// 2. Database with automatic instrumentation
	dsn := os.Getenv("DATABASE_URL")
	if dsn != "" {
		db, err := database.Open(database.Config{
			DriverName:   "postgres",
			DSN:          dsn,
			DatabaseName: "grpc_gateway",
		})
		if err != nil {
			log.Printf("[Database] Connection failed: %v", err)
		} else {
			deps.DB = db
			log.Println("[Database] Connected with OTel instrumentation")
			defer db.Close()
		}
	} else {
		log.Println("[Database] Skipped (DATABASE_URL not set)")
	}

	// 3. Redis with automatic instrumentation
	redisAddr := os.Getenv("REDIS_URL")
	if redisAddr == "" {
		redisAddr = "localhost:6379" // Default
	}

	redisClient, redisInstrErr := redisagent.NewClient(&redis.Options{
		Addr:     redisAddr,
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       0,
	})
	if redisInstrErr != nil {
		log.Printf("Warning: Redis instrumentation failed: %v", redisInstrErr)
	}

	// Test Redis connection
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	_, err := redisClient.Ping(ctx).Result()
	cancel()

	if err != nil {
		log.Printf("[Redis] Connection failed: %v (continuing without Redis)", err)
		redisClient = nil
	} else {
		deps.Redis = redisClient
		log.Println("[Redis] Connected with OTel instrumentation")
		defer redisClient.Close()
	}

	// 4. HTTP Client with automatic instrumentation
	deps.HTTPClient = httpagent.NewClient(&http.Client{
		Timeout: 10 * time.Second,
	})
	log.Println("[HTTP Client] Created with OTel instrumentation")

	log.Println("")
	log.Println("Starting services...")

	// Start gRPC server
	go startGrpcServer(deps)

	// Start HTTP gateway
	if err := startHTTPGateway(); err != nil {
		log.Fatalf("Failed to start HTTP gateway: %v", err)
	}
}

func startGrpcServer(deps *Dependencies) {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	// Create gRPC server with go-agent (automatic instrumentation)
	grpcServer := grpcgateway.NewGrpcServer()

	pb.RegisterGreeterServer(grpcServer, &server{deps: deps})

	log.Printf("[gRPC Server] Listening at %v (instrumented)", lis.Addr())
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}

func startHTTPGateway() error {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Create grpc-gateway ServeMux with go-agent
	gwMux := grpcgateway.NewGatewayMux()

	// Connect to gRPC server with automatic client instrumentation
	conn, err := grpc.NewClient(
		"localhost:50051",
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpcgateway.NewDialOption(), // Automatic OTel client tracing
	)
	if err != nil {
		return fmt.Errorf("failed to dial: %w", err)
	}
	defer conn.Close()

	if err := pb.RegisterGreeterHandler(ctx, gwMux, conn); err != nil {
		return fmt.Errorf("failed to register handler: %w", err)
	}

	// Create HTTP mux
	httpMux := http.NewServeMux()
	httpMux.Handle("/", gwMux)
	httpMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Wrap with go-agent HTTP instrumentation
	handler := grpcgateway.WrapHTTPMux(httpMux, "grpc-gateway")

	log.Println("[HTTP Gateway] Listening on :8080 (instrumented)")
	log.Println("")
	log.Println("============================================================")
	log.Println("  Span Hierarchy (Parent -> Child):")
	log.Println("  ")
	log.Println("  HTTP Server (grpc-gateway)")
	log.Println("    └── gRPC Client (/proto.Greeter/SayHello)")
	log.Println("         └── gRPC Server (/proto.Greeter/SayHello)")
	log.Println("              └── SayHello.ProcessRequest")
	log.Println("                   ├── redis.operations")
	log.Println("                   │    ├── Redis GET")
	log.Println("                   │    ├── Redis SET")
	log.Println("                   │    └── Redis INCR")
	log.Println("                   ├── database.operations")
	log.Println("                   │    ├── SELECT NOW()")
	log.Println("                   │    └── SELECT COUNT(*)")
	log.Println("                   └── external.api.call")
	log.Println("                        └── HTTP GET httpbin.org")
	log.Println("============================================================")
	log.Println("")
	log.Println("Test with:")
	log.Println("  curl -X POST http://localhost:8080/v1/greeter/hello \\")
	log.Println("    -H 'Content-Type: application/json' \\")
	log.Println("    -d '{\"name\":\"World\"}'")
	log.Println("")

	return http.ListenAndServe(":8080", handler)
}
