package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"

	"iris_example/users"

	"github.com/kataras/iris/v12"
	agent "github.com/last9/go-agent"
	irisagent "github.com/last9/go-agent/instrumentation/iris"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
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
	h := users.NewUsersHandler(c, otel.GetTracerProvider().Tracer("iris-server"))

	app := irisagent.New()

	// Routes
	app.Get("/users", h.GetUsers)
	app.Get("/users/{id}", h.GetUser)
	app.Post("/users", h.CreateUser)
	app.Put("/users/{id}", h.UpdateUser)
	app.Delete("/users/{id}", h.DeleteUser)
	app.Get("/joke", func(ctx iris.Context) {
		getRandomJoke(ctx)
	})

	log.Println("Server is running on http://localhost:8080")
	log.Fatal(app.Listen(":8080"))
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

func getRandomJoke(ctx iris.Context) {
	parentCtx := ctx.Request().Context()
	_, span := otel.GetTracerProvider().Tracer("iris-server").Start(parentCtx, "get-random-joke")
	defer span.End()

	client := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport,
		otelhttp.WithClientTrace(func(ctx context.Context) *httptrace.ClientTrace {
			return otelhttptrace.NewClientTrace(ctx)
		}),
	)}

	req, _ := http.NewRequestWithContext(parentCtx, "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		ctx.StatusCode(iris.StatusInternalServerError)
		ctx.JSON(iris.Map{"error": "Failed to fetch joke"})
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

	ctx.JSON(iris.Map{
		"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
	})
}
