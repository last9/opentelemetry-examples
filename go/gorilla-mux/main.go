package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"

	"gorilla_mux_example/last9"
	"gorilla_mux_example/users"

	"github.com/gorilla/mux"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gorilla/mux/otelmux"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

func main() {
	i := last9.NewInstrumentation()

	defer func() {
		if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	redisClient := initRedis()
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c, i.Tracer)

	r := mux.NewRouter()

	r.HandleFunc("/users", h.GetUsers).Methods("GET")
	r.HandleFunc("/users/{id}", h.GetUser).Methods("GET")
	r.HandleFunc("/users", h.CreateUser).Methods("POST")
	r.HandleFunc("/users/{id}", h.UpdateUser).Methods("PUT")
	r.HandleFunc("/users/{id}", h.DeleteUser).Methods("DELETE")
	r.HandleFunc("/joke", func(w http.ResponseWriter, r *http.Request) {
		getRandomJoke(w, r, i)
	}).Methods("GET")

	r.Use(otelmux.Middleware("gorilla-server"))

	log.Println("Server is running on http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func initRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379", // Update this with your Redis server address
	})

	if err := redisotel.InstrumentTracing(rdb); err != nil {
		log.Fatalf("failed to instrument traces for Redis client: %v", err)
		return nil
	}
	return rdb
}

func getRandomJoke(w http.ResponseWriter, r *http.Request, i *last9.Instrumentation) {
	_, span := i.Tracer.Start(r.Context(), "get-random-joke")
	defer span.End()

	client := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport,
		otelhttp.WithClientTrace(func(ctx context.Context) *httptrace.ClientTrace {
			return otelhttptrace.NewClientTrace(ctx)
		}),
	)}

	req, _ := http.NewRequestWithContext(r.Context(), "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
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

	span.SetAttributes(
		attribute.String("joke.setup", joke.Setup),
		attribute.String("joke.punchline", joke.Punchline),
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
	})
}
