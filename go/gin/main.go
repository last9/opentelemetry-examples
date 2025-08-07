package main

import (
	"context"
	"encoding/json"
	"fmt"
	"gin_example/common"
	"gin_example/users"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"

	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/plugin/opentelemetry/tracing"
)

// Post is a GORM model for demonstration
// You can move this to a separate file if needed
// It will be auto-migrated
type Post struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	Title   string `json:"title"`
	Content string `json:"content"`
}

func initGormDB() (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open("gorm.db"), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	// Add OpenTelemetry tracing plugin
	if err := db.Use(tracing.NewPlugin()); err != nil {
		return nil, err
	}
	return db, nil
}

// Enhanced Tracing Middleware with Exception Handling
func TracingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tracer := otel.Tracer("gin-server")
		spanName := fmt.Sprintf("%s %s", c.Request.Method, c.Request.URL.Path)
		
		ctx, span := tracer.Start(c.Request.Context(), spanName)
		defer span.End()
		
		// Store span in Gin context
		c.Set("span", span)
		c.Set("traceContext", ctx)
		
		// Update request context
		c.Request = c.Request.WithContext(ctx)
		
		// Add request attributes to span
		span.SetAttributes(
			attribute.String("http.method", c.Request.Method),
			attribute.String("http.url", c.Request.URL.String()),
			attribute.String("http.user_agent", c.Request.UserAgent()),
			attribute.String("http.remote_addr", c.ClientIP()),
		)
		
		// Capture start time for duration calculation
		startTime := time.Now()
		
		// Use defer to ensure we capture the final status and duration
		defer func() {
			duration := time.Since(startTime)
			span.SetAttributes(
				attribute.Int("http.status_code", c.Writer.Status()),
				attribute.Int64("http.duration_ms", duration.Milliseconds()),
			)
			
			// Set span status based on response
			if c.Writer.Status() >= 400 {
				span.SetStatus(codes.Error, fmt.Sprintf("HTTP %d", c.Writer.Status()))
			} else {
				span.SetStatus(codes.Ok, "")
			}
		}()
		
		c.Next()
	}
}

// This example demonstrates BOTH:
// 1. otelsql instrumentation (raw SQL, see /users endpoints)
// 2. GORM + OpenTelemetry plugin (see /posts endpoints)
//
// See README for details.
func main() {
	r := gin.Default()
	i := NewInstrumentation()
	mp, err := initMetrics()
	if err != nil {
		log.Fatalf("failed to initialize metrics: %v", err)
	}

	// Handle shutdown properly so nothing leaks.
	defer func() {
		if err := mp.Shutdown(context.Background()); err != nil {
			log.Println(err)
		}
	}()

	// Register as global meter provider so that it can be used via otel.Meter
	// and accessed using otel.GetMeterProvider.
	// Most instrumentation libraries use the global meter provider as default.
	// If the global meter provider is not set then a no-op implementation
	// is used, which fails to generate data.
	otel.SetMeterProvider(mp)

	defer func() {
		if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Initialize Redis client
	redisClient := initRedis()

	// Initialize the controller with Redis client
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c, i.Tracer)

	// Use enhanced tracing middleware with detailed exception handling
	r.Use(TracingMiddleware())

	// --- otelsql example: /users endpoints use raw SQL with otelsql instrumentation ---
	// See users/controller.go for otelsql setup and usage
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)
	// New route for fetching a random joke
	r.GET("/joke", func(c *gin.Context) {
		getRandomJoke(c, i)
	})

	db, err := initGormDB()
	if err != nil {
		log.Fatalf("failed to initialize GORM: %v", err)
	}
	// Auto-migrate Post model
	db.AutoMigrate(&Post{})

	// --- GORM + OpenTelemetry example: /posts endpoints use GORM with otel plugin ---
	r.GET("/posts", func(c *gin.Context) {
		var posts []Post
		if err := db.WithContext(c.Request.Context()).Find(&posts).Error; err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}
		c.JSON(200, posts)
	})

	r.POST("/posts", func(c *gin.Context) {
		var post Post
		if err := c.ShouldBindJSON(&post); err != nil {
			// Record exception with detailed information
			common.RecordExceptionInSpan(c, "Invalid JSON input", 
				"error_type", "validation_error",
				"field", "request_body",
				"details", err.Error())
			c.JSON(400, gin.H{"error": "Invalid input"})
			return
		}
		if err := db.WithContext(c.Request.Context()).Create(&post).Error; err != nil {
			// Record database exception with stack trace
			common.RecordExceptionWithStack(c, err, 
				"operation", "create_post",
				"table", "posts",
				"post_title", post.Title)
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}
		c.JSON(201, post)
	})

	// Example endpoints demonstrating exception handling
	r.GET("/test-exception", func(c *gin.Context) {
		// Simulate a panic
		defer func() {
			if r := recover(); r != nil {
				common.RecordExceptionInSpan(c, "Panic occurred", 
					"panic_value", fmt.Sprintf("%v", r),
					"endpoint", "/test-exception")
				c.JSON(500, gin.H{"error": "Internal server error"})
			}
		}()
		
		// This will cause a panic
		panic("Test panic for exception handling")
	})

	r.GET("/test-error", func(c *gin.Context) {
		// Simulate an error
		err := fmt.Errorf("simulated database connection error")
		common.RecordExceptionWithStack(c, err,
			"component", "database",
			"operation", "connection",
			"endpoint", "/test-error")
		c.JSON(500, gin.H{"error": "Database error"})
	})

	r.Run()
}

func initRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379", // Update this with your Redis server address
	})

	// Setup traces for redis instrumentation
	if err := redisotel.InstrumentTracing(rdb); err != nil {
		log.Fatalf("failed to instrument traces for Redis client: %v", err)
		return nil
	}
	return rdb
}

func getRandomJoke(c *gin.Context, i *Instrumentation) {
	// Start a new span for the external API call
	ctx := c.Request.Context()
	ctx, span := i.Tracer.Start(ctx, "get-random-joke")
	defer span.End()

	// Create an HTTP client with OpenTelemetry instrumentation
	client := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport,
		// By setting the otelhttptrace client in this transport, it can be
		// injected into the context after the span is started, which makes the
		// httptrace spans children of the transport one.
		otelhttp.WithClientTrace(func(ctx context.Context) *httptrace.ClientTrace {
			return otelhttptrace.NewClientTrace(ctx)
		}))}

	// Make a request to the external API
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch joke"})
		return
	}
	defer resp.Body.Close()

	// Read and parse the response
	body, _ := io.ReadAll(resp.Body)
	var joke struct {
		Setup     string `json:"setup"`
		Punchline string `json:"punchline"`
	}
	json.Unmarshal(body, &joke)

	// Add attributes to the external API call span
	span.SetAttributes(
		attribute.String("joke.setup", joke.Setup),
		attribute.String("joke.punchline", joke.Punchline),
	)

	c.JSON(http.StatusOK, joke)
}
