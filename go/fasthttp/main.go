package main

import (
	"context"
	"encoding/json"
	"fasthttp_example/users"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"

	"github.com/fasthttp/router"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
	"github.com/valyala/fasthttp"
	agent "github.com/last9/go-agent"
	fasthttpagent "github.com/last9/go-agent/instrumentation/fasthttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

func main() {
	agent.Start()
	defer agent.Shutdown()

	// Initialize Redis client
	redisClient := initRedis()

	// Initialize the controller with Redis client
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c, otel.GetTracerProvider().Tracer("fasthttp-server"))

	r := router.New()

	// Routes
	r.GET("/users", h.GetUsers)
	r.GET("/users/{id}", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/{id}", h.UpdateUser)
	r.DELETE("/users/{id}", h.DeleteUser)
	r.GET("/joke", func(ctx *fasthttp.RequestCtx) {
		getRandomJoke(ctx)
	})

	log.Println("Server is running on http://localhost:8080")
	log.Fatal(fasthttp.ListenAndServe(":8080", fasthttpagent.Middleware(r.Handler)))
}

func initRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
	})

	if err := redisotel.InstrumentTracing(rdb); err != nil {
		log.Fatalf("failed to instrument traces for Redis client: %v", err)
		return nil
	}
	return rdb
}

func getRandomJoke(ctx *fasthttp.RequestCtx) {
	otelCtx := fasthttpagent.ContextFromRequest(ctx)
	_, span := otel.GetTracerProvider().Tracer("fasthttp-server").Start(otelCtx, "get-random-joke")
	defer span.End()

	client := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport,
		otelhttp.WithClientTrace(func(ctx context.Context) *httptrace.ClientTrace {
			return otelhttptrace.NewClientTrace(ctx)
		}))}

	req, _ := http.NewRequestWithContext(otelCtx, "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString("Failed to fetch joke")
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

	ctx.SetStatusCode(fasthttp.StatusOK)
	ctx.SetBodyString(fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline))
}
