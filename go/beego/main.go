package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"beego_example/users"

	"github.com/beego/beego/v2/client/httplib"
	"github.com/beego/beego/v2/server/web"
	"github.com/redis/go-redis/v9"

	// OpenTelemetry imports (Harbor style)
	otelhttp "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

var usersHandler *users.UsersHandler

func main() {
	shutdown, err := setupTracer()
	if err != nil {
		log.Fatalf("failed to setup OpenTelemetry: %v", err)
	}
	defer shutdown()

	// Initialize Redis client
	redisClient := initRedis()

	// Initialize the controller with Redis client
	c := users.NewUsersController(redisClient)
	usersHandler = users.NewUsersHandler(c, nil)

	// Beego controller registration
	web.Router("/users", &UsersControllerWrapper{}, "get:GetUsers")
	web.Router("/users/:id", &UsersControllerWrapper{}, "get:GetUser")
	web.Router("/users", &UsersControllerWrapper{}, "post:CreateUser")
	web.Router("/users/:id", &UsersControllerWrapper{}, "put:UpdateUser")
	web.Router("/users/:id", &UsersControllerWrapper{}, "delete:DeleteUser")
	web.Router("/joke", &JokeController{}, "get:GetJoke")

	log.Println("Server is running on http://localhost:8080")
	// Wrap Beego's handler with otelhttp for tracing incoming requests
	handler := otelhttp.NewHandler(web.BeeApp.Handlers, "beego-server")
	http.ListenAndServe(":8080", handler)
}

func setupTracer() (func(), error) {
	exporter, err := otlptracehttp.New(context.Background())
	if err != nil {
		return nil, err
	}
	res, err := resource.New(context.Background(),
		resource.WithAttributes(
			semconv.ServiceNameKey.String("beego-app"),
		),
	)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	return func() { _ = tp.Shutdown(context.Background()) }, nil
}

func initRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379", // Update this with your Redis server address
	})

	// Setup traces for redis instrumentation
	// if err := redisotel.InstrumentTracing(rdb); err != nil {
	// 	log.Fatalf("failed to instrument traces for Redis client: %v", err)
	// 	return nil
	// }
	return rdb
}

// Beego controller wrappers

type UsersControllerWrapper struct {
	web.Controller
}

func (c *UsersControllerWrapper) GetUsers() {
	usersHandler.GetUsersBeego(&c.Controller)
}
func (c *UsersControllerWrapper) GetUser() {
	usersHandler.GetUserBeego(&c.Controller)
}
func (c *UsersControllerWrapper) CreateUser() {
	usersHandler.CreateUserBeego(&c.Controller)
}
func (c *UsersControllerWrapper) UpdateUser() {
	usersHandler.UpdateUserBeego(&c.Controller)
}
func (c *UsersControllerWrapper) DeleteUser() {
	usersHandler.DeleteUserBeego(&c.Controller)
}

type JokeController struct {
	web.Controller
}

func (c *JokeController) GetJoke() {
	getRandomJokeBeego(&c.Controller)
}

// Adapted joke handler for Beego
func getRandomJokeBeego(ctx *web.Controller) {
	// Use Beego's httplib for outgoing HTTP request
	req := httplib.Get("https://official-joke-api.appspot.com/random_joke")
	resp, err := req.Response()
	if err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to fetch joke"}
		ctx.ServeJSON()
		return
	}
	defer resp.Body.Close()

	var joke struct {
		Setup     string `json:"setup"`
		Punchline string `json:"punchline"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&joke); err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to parse joke"}
		ctx.ServeJSON()
		return
	}

	ctx.Data["json"] = map[string]string{
		"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
	}
	ctx.ServeJSON()
}
