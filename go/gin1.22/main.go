package main

import (
	"context"
	"gin1.22/users"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.16.0"
)

func main() {
	// Initialize OpenTelemetry
	cleanup := initOpenTelemetry()
	defer cleanup()

	// Create Gin router with OpenTelemetry middleware
	r := gin.Default()
	r.Use(otelgin.Middleware("gin-otel-example"))

	// Initialize users controller and handler
	controller := users.NewUsersController()
	tracer := otel.Tracer("gin-otel-example")
	handler := users.NewUsersHandler(controller, tracer)

	// Basic health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status": "healthy",
			"time":   time.Now().UTC(),
		})
	})

	// Users API routes
	r.GET("/users", handler.GetUsers)
	r.GET("/users/:id", handler.GetUser)
	r.POST("/users", handler.CreateUser)
	r.PUT("/users/:id", handler.UpdateUser)
	r.DELETE("/users/:id", handler.DeleteUser)

	log.Println("Server starting on :8080")
	log.Println("Available endpoints:")
	log.Println("  GET    /health")
	log.Println("  GET    /users")
	log.Println("  GET    /users/:id")
	log.Println("  POST   /users")
	log.Println("  PUT    /users/:id")
	log.Println("  DELETE /users/:id")
	log.Fatal(r.Run(":8080"))
}

func initOpenTelemetry() func() {
	ctx := context.Background()

	// Debug: Print environment variables
	log.Printf("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: %s", os.Getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"))
	log.Printf("OTEL_EXPORTER_OTLP_TRACES_HEADERS: %s", os.Getenv("OTEL_EXPORTER_OTLP_TRACES_HEADERS"))
	log.Printf("OTEL_RESOURCE_ATTRIBUTES: %s", os.Getenv("OTEL_RESOURCE_ATTRIBUTES"))

	// Create resource with service attributes
	res, err := resource.New(ctx,
		resource.WithAttributes(
			// Service identification
			semconv.ServiceNameKey.String("gin-users-api"),        // Updated service name
			semconv.ServiceVersionKey.String("1.0.0"),
			semconv.ServiceInstanceIDKey.String("instance-1"),
			// Environment information
			semconv.DeploymentEnvironmentKey.String("development"), // or "production", "staging"
			// Additional custom attributes
			semconv.ServiceNamespaceKey.String("users-service"),
		),
		// You can also detect resource attributes automatically
		resource.WithFromEnv(),   // Reads from OTEL_RESOURCE_ATTRIBUTES env var
		resource.WithProcess(),   // Adds process info
		resource.WithOS(),        // Adds OS info
		resource.WithHost(),      // Adds host info
	)
	if err != nil {
		log.Fatal("Failed to create resource:", err)
	}

	// Debug: Print final resource attributes
	for _, attr := range res.Attributes() {
		log.Printf("Resource attribute: %s = %s", attr.Key, attr.Value.AsString())
	}

	// Let OpenTelemetry handle the environment variables automatically
	// This should use OTEL_EXPORTER_OTLP_TRACES_ENDPOINT and OTEL_EXPORTER_OTLP_TRACES_HEADERS
	traceExporter, err := otlptracehttp.New(ctx)
	if err != nil {
		log.Fatal("Failed to create trace exporter:", err)
	}

	// Create trace provider with more frequent batch processing
	traceProvider := trace.NewTracerProvider(
		trace.WithBatcher(traceExporter,
			trace.WithBatchTimeout(2*time.Second),    // Export every 2 seconds
			trace.WithMaxExportBatchSize(10),         // Smaller batch size
		),
		trace.WithResource(res),
	)

	// Set global providers
	otel.SetTracerProvider(traceProvider)

	log.Println("OpenTelemetry initialized successfully")

	// Return cleanup function
	return func() {
		log.Println("Shutting down OpenTelemetry...")
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := traceProvider.Shutdown(ctx); err != nil {
			log.Printf("Failed to shutdown tracer provider: %v", err)
		} else {
			log.Println("OpenTelemetry shut down successfully")
		}
	}
}