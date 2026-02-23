package main

import (
	"chi1.22/users"
	"encoding/json"
	"io"
	"log"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/last9/go-agent"
	chiagent "github.com/last9/go-agent/instrumentation/chi"
	httpagent "github.com/last9/go-agent/integrations/http"
	redisagent "github.com/last9/go-agent/integrations/redis"
	"github.com/redis/go-redis/v9"
)

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	r := chi.NewRouter()

	// Initialize Redis client with go-agent
	redisClient := initRedis()

	// Initialize the controller with Redis client
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c, nil) // No longer need tracer

	// Chi middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Routes
	r.Get("/users", h.GetUsers)
	r.Get("/users/{id}", h.GetUser)
	r.Post("/users", h.CreateUser)
	r.Put("/users/{id}", h.UpdateUser)
	r.Delete("/users/{id}", h.DeleteUser)

	// New route for fetching a random joke
	r.Get("/joke", getRandomJoke)

	// Wrap router with go-agent instrumentation AFTER defining routes
	handler := chiagent.Use(r)

	log.Println("✓ Chi server starting on :8080 (instrumented by go-agent)")
	http.ListenAndServe(":8080", handler)
}

func initRedis() *redis.Client {
	// Create Redis client with go-agent (automatic instrumentation)
	rdb, err := redisagent.NewClient(&redis.Options{
		Addr: "localhost:6379",
	})
	if err != nil {
		log.Printf("Warning: Redis instrumentation failed: %v", err)
	}
	return rdb
}

func getRandomJoke(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Create an HTTP client with go-agent (automatic instrumentation)
	client := httpagent.NewClient(&http.Client{})

	// Make a request to the external API (automatically traced by go-agent)
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
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

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(joke)
}
