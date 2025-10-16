package main

import (
	"chi1.22/users"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"github.com/riandyrn/otelchi"
)

func main() {
	r := chi.NewRouter()
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

	// Chi middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(otelchi.Middleware("chi-server", otelchi.WithChiRoutes(r)))

	// Routes
	r.Get("/users", h.GetUsers)
	r.Get("/users/{id}", h.GetUser)
	r.Post("/users", h.CreateUser)
	r.Put("/users/{id}", h.UpdateUser)
	r.Delete("/users/{id}", h.DeleteUser)

	// New route for fetching a random joke
	r.Get("/joke", func(w http.ResponseWriter, r *http.Request) {
		getRandomJoke(w, r, i)
	})

	log.Println("Server starting on :8080")
	http.ListenAndServe(":8080", r)
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

func getRandomJoke(w http.ResponseWriter, r *http.Request, i *Instrumentation) {
	// Start a new span for the external API call
	ctx := r.Context()
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
		http.Error(w, `{"error": "Failed to fetch joke"}`, http.StatusInternalServerError)
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

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(joke)
}
