// Cloud Run Go Gin Application with OpenTelemetry
// Sends traces, logs, and metrics to Last9
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"
)

var (
	tracer         trace.Tracer
	meter          metric.Meter
	requestCounter metric.Int64Counter
	requestLatency metric.Float64Histogram
)

// User represents a user entity
type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at,omitempty"`
}

// LogEntry represents a structured log entry for Cloud Logging
type LogEntry struct {
	Severity   string                 `json:"severity"`
	Message    string                 `json:"message"`
	Timestamp  string                 `json:"timestamp"`
	Service    string                 `json:"service,omitempty"`
	Revision   string                 `json:"revision,omitempty"`
	Trace      string                 `json:"logging.googleapis.com/trace,omitempty"`
	SpanID     string                 `json:"logging.googleapis.com/spanId,omitempty"`
	Extra      map[string]interface{} `json:"extra,omitempty"`
}

// structuredLog outputs a JSON-formatted log entry with trace correlation
func structuredLog(ctx context.Context, level, message string, extra map[string]interface{}) {
	entry := LogEntry{
		Severity:  level,
		Message:   message,
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Service:   os.Getenv("K_SERVICE"),
		Revision:  os.Getenv("K_REVISION"),
		Extra:     extra,
	}

	// Add trace correlation
	span := trace.SpanFromContext(ctx)
	if span.SpanContext().IsValid() {
		projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
		if projectID != "" {
			entry.Trace = fmt.Sprintf("projects/%s/traces/%s", projectID, span.SpanContext().TraceID().String())
			entry.SpanID = span.SpanContext().SpanID().String()
		}
	}

	jsonBytes, _ := json.Marshal(entry)
	fmt.Println(string(jsonBytes))
}

func initMetrics() {
	var err error

	meter = otel.Meter("cloud-run-gin")

	requestCounter, err = meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("Total number of HTTP requests"),
		metric.WithUnit("1"),
	)
	if err != nil {
		log.Printf("Failed to create request counter: %v", err)
	}

	requestLatency, err = meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("HTTP request duration in seconds"),
		metric.WithUnit("s"),
	)
	if err != nil {
		log.Printf("Failed to create request latency histogram: %v", err)
	}
}

// metricsMiddleware records request metrics
func metricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		c.Next()

		duration := time.Since(start).Seconds()

		attrs := []attribute.KeyValue{
			attribute.String("http.method", c.Request.Method),
			attribute.String("http.route", c.FullPath()),
			attribute.Int("http.status_code", c.Writer.Status()),
		}

		requestCounter.Add(c.Request.Context(), 1, metric.WithAttributes(attrs...))
		requestLatency.Record(c.Request.Context(), duration, metric.WithAttributes(attrs[:2]...))
	}
}

func main() {
	// Initialize OpenTelemetry
	tp, mp := initTelemetry()
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		structuredLog(ctx, "INFO", "Shutting down telemetry providers", nil)

		if err := tp.Shutdown(ctx); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
		if err := mp.Shutdown(ctx); err != nil {
			log.Printf("Error shutting down meter provider: %v", err)
		}
	}()

	// Initialize tracer and metrics
	tracer = otel.Tracer("cloud-run-gin")
	initMetrics()

	// Set up Gin
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()

	// Add middleware
	r.Use(gin.Recovery())
	r.Use(otelgin.Middleware(os.Getenv("OTEL_SERVICE_NAME")))
	r.Use(metricsMiddleware())

	// Routes
	r.GET("/", homeHandler)
	r.GET("/users", getUsersHandler)
	r.GET("/users/:id", getUserHandler)
	r.POST("/users", createUserHandler)
	r.GET("/error", errorHandler)
	r.GET("/health", healthHandler)
	r.GET("/ready", readyHandler)

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	// Graceful shutdown
	go func() {
		structuredLog(context.Background(), "INFO", fmt.Sprintf("Starting server on port %s", port), map[string]interface{}{"port": port})
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	structuredLog(context.Background(), "INFO", "Received shutdown signal", nil)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}

	structuredLog(context.Background(), "INFO", "Server shutdown complete", nil)
}

func homeHandler(c *gin.Context) {
	ctx := c.Request.Context()
	structuredLog(ctx, "INFO", "Home endpoint accessed", nil)

	c.JSON(http.StatusOK, gin.H{
		"message":  "Hello from Cloud Run with OpenTelemetry!",
		"service":  os.Getenv("K_SERVICE"),
		"revision": os.Getenv("K_REVISION"),
	})
}

func getUsersHandler(c *gin.Context) {
	ctx := c.Request.Context()

	_, span := tracer.Start(ctx, "fetch_users_from_database",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
		))
	defer span.End()

	// Simulate database query
	users := []User{
		{ID: 1, Name: "Alice", Email: "alice@example.com"},
		{ID: 2, Name: "Bob", Email: "bob@example.com"},
		{ID: 3, Name: "Charlie", Email: "charlie@example.com"},
	}

	span.SetAttributes(attribute.Int("user.count", len(users)))
	span.AddEvent("Users fetched successfully")

	structuredLog(ctx, "INFO", fmt.Sprintf("Returning %d users", len(users)), nil)

	c.JSON(http.StatusOK, users)
}

func getUserHandler(c *gin.Context) {
	ctx := c.Request.Context()
	idParam := c.Param("id")

	_, span := tracer.Start(ctx, "fetch_user_by_id",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
			attribute.String("user.id_param", idParam),
		))
	defer span.End()

	var userID int
	if _, err := fmt.Sscanf(idParam, "%d", &userID); err != nil || userID <= 0 {
		span.SetAttributes(attribute.Bool("error", true))
		span.SetStatus(codes.Error, "Invalid user ID")
		structuredLog(ctx, "WARNING", fmt.Sprintf("Invalid user ID requested: %s", idParam), nil)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	span.SetAttributes(attribute.Int("user.id", userID))

	// Simulate user lookup
	user := User{
		ID:    userID,
		Name:  fmt.Sprintf("User %d", userID),
		Email: fmt.Sprintf("user%d@example.com", userID),
	}

	structuredLog(ctx, "INFO", fmt.Sprintf("Retrieved user %d", userID), nil)

	c.JSON(http.StatusOK, user)
}

func createUserHandler(c *gin.Context) {
	ctx := c.Request.Context()

	_, span := tracer.Start(ctx, "create_user",
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "INSERT"),
		))
	defer span.End()

	var input struct {
		Name  string `json:"name" binding:"required"`
		Email string `json:"email" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		span.SetAttributes(attribute.Bool("error", true))
		span.SetStatus(codes.Error, "Invalid input")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Name and email are required"})
		return
	}

	// Simulate user creation
	newUser := User{
		ID:        int(time.Now().UnixNano() % 10000),
		Name:      input.Name,
		Email:     input.Email,
		CreatedAt: time.Now(),
	}

	span.SetAttributes(attribute.Int("user.id", newUser.ID))
	span.AddEvent("User created successfully")

	structuredLog(ctx, "INFO", fmt.Sprintf("Created user %d", newUser.ID), map[string]interface{}{"userName": input.Name})

	c.JSON(http.StatusCreated, newUser)
}

func errorHandler(c *gin.Context) {
	ctx := c.Request.Context()

	_, span := tracer.Start(ctx, "error_operation")
	defer span.End()

	// Simulate an error
	err := fmt.Errorf("this is a simulated error for testing")

	span.SetAttributes(attribute.Bool("error", true))
	span.RecordError(err)
	span.SetStatus(codes.Error, err.Error())

	structuredLog(ctx, "ERROR", fmt.Sprintf("Error occurred: %v", err), map[string]interface{}{"error": err.Error()})

	c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
}

func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "healthy"})
}

func readyHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}
