package main

import (
	"context"
	"gin_example/users"
	"log"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
)

func main() {
	r := gin.Default()
	i := NewInstrumentation()

	defer func() {
		if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Initialize the controller
	c := users.NewUsersControllers()
	h := users.NewUsersHandler(c, i.Tracer)

	r.Use(otelgin.Middleware("gin-server"))

	// Routes
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)

	r.Run()
}
