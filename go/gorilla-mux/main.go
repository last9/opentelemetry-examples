package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"

	"gorilla_mux_example/users"

	"github.com/last9/go-agent"
	gorillaagent "github.com/last9/go-agent/instrumentation/gorilla"
	httpagent "github.com/last9/go-agent/integrations/http"
	redisagent "github.com/last9/go-agent/integrations/redis"
	"github.com/redis/go-redis/v9"
)

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	redisClient := initRedis()
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c, nil) // No longer need tracer

	// Create router with go-agent instrumentation
	r := gorillaagent.NewRouter()

	r.HandleFunc("/users", h.GetUsers).Methods("GET")
	r.HandleFunc("/users/{id}", h.GetUser).Methods("GET")
	r.HandleFunc("/users", h.CreateUser).Methods("POST")
	r.HandleFunc("/users/{id}", h.UpdateUser).Methods("PUT")
	r.HandleFunc("/users/{id}", h.DeleteUser).Methods("DELETE")
	r.HandleFunc("/joke", getRandomJoke).Methods("GET")

	log.Println("✓ Gorilla Mux server running on http://localhost:8080 (instrumented by go-agent)")
	log.Fatal(http.ListenAndServe(":8080", r))
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
	// Create HTTP client with go-agent (automatic instrumentation)
	client := httpagent.NewClient(&http.Client{})

	req, _ := http.NewRequestWithContext(r.Context(), "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to fetch joke"})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var joke struct {
		Setup     string `json:"setup"`
		Punchline string `json:"punchline"`
	}
	json.Unmarshal(body, &joke)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
	})
}
