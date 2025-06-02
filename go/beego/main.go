package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	// "net/http"

	// "iris_example/last9"
	"iris_example/users"

	// "github.com/kataras/iris/v12"
	"github.com/astaxie/beego"
	"github.com/redis/go-redis/v9"

	// OpenTelemetry imports (Harbor style)
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
	beego.Router("/users", &UsersControllerWrapper{}, "get:GetUsers")
	beego.Router("/users/:id", &UsersControllerWrapper{}, "get:GetUser")
	beego.Router("/users", &UsersControllerWrapper{}, "post:CreateUser")
	beego.Router("/users/:id", &UsersControllerWrapper{}, "put:UpdateUser")
	beego.Router("/users/:id", &UsersControllerWrapper{}, "delete:DeleteUser")
	beego.Router("/joke", &JokeController{}, "get:GetJoke")

	log.Println("Server is running on http://localhost:8080")
	beego.Run()
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
	beego.Controller
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
	beego.Controller
}

func (c *JokeController) GetJoke() {
	getRandomJokeBeego(&c.Controller)
}

// Adapted joke handler for Beego
func getRandomJokeBeego(ctx *beego.Controller) {
	// Use standard library net/http for outgoing HTTP request
	// TODO: Instrument with otelhttp if tracing is required
	resp, err := http.Get("https://official-joke-api.appspot.com/random_joke")
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
