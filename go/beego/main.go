package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"beego_example/users"

	"github.com/beego/beego/v2/client/httplib"
	"github.com/beego/beego/v2/server/web"
	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"

	// Instrumentation
	"beego_example/last9"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
)

var usersHandler *users.UsersHandler

func main() {
	// Initialize OpenTelemetry instrumentation using last9 package
	i := last9.NewInstrumentation("beego-app")
	defer func() {
		if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
			// Remove debug log, optionally handle error if needed
		}
	}()

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
	web.Router("/joke2", &Joke2Controller{})

	// Remove debug log for server start
	web.Run()
}

func initRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379", // Update this with your Redis server address
	})

	// Setup traces for redis instrumentation
	if err := redisotel.InstrumentTracing(rdb); err != nil {
		// Remove fatal log, just panic or return nil
		panic("failed to instrument traces for Redis client: " + err.Error())
		return nil
	}
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
	last9.WrapBeegoHandler("beego-app", getRandomJokeBeego)(&c.Controller)
}

// Joke2Controller for /joke2 endpoint using net/http + otelhttp

type Joke2Controller struct {
	web.Controller
}

func (c *Joke2Controller) Get() {
	last9.WrapBeegoHandler("beego-app", func(ctx *web.Controller) {
		client := http.Client{
			Transport: otelhttp.NewTransport(http.DefaultTransport),
		}
		req, err := http.NewRequestWithContext(ctx.Ctx.Request.Context(), "GET", "https://official-joke-api.appspot.com/random_joke", nil)
		if err != nil {
			ctx.Ctx.Output.SetStatus(500)
			ctx.Data["json"] = map[string]string{"error": "Failed to create request"}
			ctx.ServeJSON()
			return
		}
		resp, err := client.Do(req)
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

		ctx.Ctx.Output.SetStatus(200)
		ctx.Data["json"] = map[string]string{
			"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
		}
		ctx.ServeJSON()
	})(&c.Controller)
}

// Instrument Beego's httplib in /joke by manually creating a span
func getRandomJokeBeego(ctx *web.Controller) {
	// Manual span for outgoing call
	tracer := otel.Tracer("beego-app")
	spanCtx, span := tracer.Start(ctx.Ctx.Request.Context(), "external.httplib.joke-api")
	defer span.End()

	req := httplib.Get("https://official-joke-api.appspot.com/random_joke")
	// Propagate context manually
	req.SetTransport(&http.Transport{})
	// Set headers for propagation
	otel.GetTextMapPropagator().Inject(spanCtx, propagation.HeaderCarrier(req.GetRequest().Header))

	resp, err := req.Response()
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "Failed to fetch joke")
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
		span.RecordError(err)
		span.SetStatus(codes.Error, "Failed to parse joke")
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to parse joke"}
		ctx.ServeJSON()
		return
	}

	span.SetStatus(codes.Ok, "OK")
	ctx.Ctx.Output.SetStatus(200)
	ctx.Data["json"] = map[string]string{
		"joke": fmt.Sprintf("Joke: %s\n\n%s", joke.Setup, joke.Punchline),
	}
	ctx.ServeJSON()
}
