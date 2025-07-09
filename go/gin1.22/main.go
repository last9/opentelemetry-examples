package main

import (
	"context"
	"encoding/json"
	"gin1.22/users"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

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

	r.Use(otelgin.Middleware("gin-server"))

	// Routes
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)
	// New route for fetching a random joke
	r.GET("/joke", func(c *gin.Context) {
		getRandomJoke(c, i)
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