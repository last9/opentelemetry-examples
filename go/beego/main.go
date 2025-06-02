package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"beego_example/users"

	"github.com/beego/beego/v2/client/httplib"
	"github.com/beego/beego/v2/server/web"
	"github.com/redis/go-redis/v9"

	// Instrumentation
	"beego_example/last9"
)

var usersHandler *users.UsersHandler

func main() {
	// Initialize OpenTelemetry instrumentation using last9 package
	i := last9.NewInstrumentation("beego-app")
	defer func() {
		if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Add Beego Otel middleware as a filter
	web.InsertFilter("/*", web.BeforeRouter, last9.BeegoOtelMiddleware("beego-app"))

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
	web.Run()
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
