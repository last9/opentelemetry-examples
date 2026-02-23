package main

import (
	"encoding/json"
	"gin1.22/users"
	"io"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/last9/go-agent"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
	httpagent "github.com/last9/go-agent/integrations/http"
	redisagent "github.com/last9/go-agent/integrations/redis"
	"github.com/redis/go-redis/v9"
)

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	// Initialize Redis client with go-agent
	redisClient := initRedis()

	// Initialize the controller with Redis client
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c)

	// Create Gin router with go-agent instrumentation
	r := ginagent.Default()

	// Routes
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)
	// New route for fetching a random joke
	r.GET("/joke", getRandomJoke)

	r.Run()
}

func initRedis() *redis.Client {
	// Create Redis client with go-agent (automatic instrumentation)
	rdb, err := redisagent.NewClient(&redis.Options{
		Addr: "localhost:6379",
	})
	if err != nil {
		log.Printf("Warning: Redis instrumentation failed: %v", err)
	}
	log.Println("✓ Redis client connected with go-agent instrumentation")
	return rdb
}

func getRandomJoke(c *gin.Context) {
	ctx := c.Request.Context()

	// Create HTTP client with go-agent (automatic instrumentation)
	client := httpagent.NewClient(&http.Client{})

	// Make a request to the external API (automatically traced)
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch joke"})
		return
	}
	defer resp.Body.Close()

	// Read and parse the response
	body, _ := io.ReadAll(resp.Body)
	var joke struct {
		Setup     string `json:"setup"`
		Punchline string `json:"punchline"`
	}
	json.Unmarshal(body, &joke)

	c.JSON(http.StatusOK, joke)
}