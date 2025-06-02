package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"

	// "iris_example/last9"
	"iris_example/users"

	// "github.com/kataras/iris/v12"
	"github.com/astaxie/beego"
	"github.com/redis/go-redis/v9"
	// "go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	// "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	// "go.opentelemetry.io/otel/attribute"
	// "go.opentelemetry.io/otel/codes"
)

var usersHandler *users.UsersHandler

func main() {
	// i := last9.NewInstrumentation()

	// defer func() {
	// 	if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
	// 		log.Printf("Error shutting down tracer provider: %v", err)
	// 	}
	// }()

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
	// External API call logic (no tracing)
	resp, err := http.Get("https://official-joke-api.appspot.com/random_joke")
	if err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to fetch joke"}
		ctx.ServeJSON()
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var joke struct {
		Setup     string `json:"setup"`
		Punchline string `json:"punchline"`
	}
	json.Unmarshal(body, &joke)

	ctx.Data["json"] = map[string]string{
		"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
	}
	ctx.ServeJSON()
}
