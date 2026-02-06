package main

import (
	"encoding/json"
	"fmt"
	"gin_example/common"
	"gin_example/users"
	"io"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/last9/go-agent"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
	httpagent "github.com/last9/go-agent/integrations/http"
	redisagent "github.com/last9/go-agent/integrations/redis"
	"github.com/redis/go-redis/v9"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/plugin/opentelemetry/tracing"
)

// Post is a GORM model for demonstration
// You can move this to a separate file if needed
// It will be auto-migrated
type Post struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	Title   string `json:"title"`
	Content string `json:"content"`
}

func initGormDB() (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open("gorm.db"), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	// GORM keeps its own OpenTelemetry tracing plugin (go-agent doesn't support GORM yet)
	// It will use the global tracer provider set up by go-agent
	if err := db.Use(tracing.NewPlugin()); err != nil {
		return nil, err
	}
	return db, nil
}

// This example demonstrates BOTH:
// 1. otelsql instrumentation (raw SQL, see /users endpoints)
// 2. GORM + OpenTelemetry plugin (see /posts endpoints)
//
// See README for details.
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

	// --- otelsql example: /users endpoints use raw SQL with otelsql instrumentation ---
	// See users/controller.go for otelsql setup and usage
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)
	// New route for fetching a random joke
	r.GET("/joke", getRandomJoke)

	db, err := initGormDB()
	if err != nil {
		log.Fatalf("failed to initialize GORM: %v", err)
	}
	// Auto-migrate Post model
	db.AutoMigrate(&Post{})

	// --- GORM + OpenTelemetry example: /posts endpoints use GORM with otel plugin ---
	r.GET("/posts", func(c *gin.Context) {
		var posts []Post
		if err := db.WithContext(c.Request.Context()).Find(&posts).Error; err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}
		c.JSON(200, posts)
	})

	r.POST("/posts", func(c *gin.Context) {
		var post Post
		if err := c.ShouldBindJSON(&post); err != nil {
			// Record exception with detailed information
			common.RecordExceptionInSpan(c, "Invalid JSON input", 
				"error_type", "validation_error",
				"field", "request_body",
				"details", err.Error())
			c.JSON(400, gin.H{"error": "Invalid input"})
			return
		}
		if err := db.WithContext(c.Request.Context()).Create(&post).Error; err != nil {
			// Record database exception with stack trace
			common.RecordExceptionWithStack(c, err, 
				"operation", "create_post",
				"table", "posts",
				"post_title", post.Title)
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}
		c.JSON(201, post)
	})

	// Example endpoints demonstrating exception handling
	r.GET("/test-exception", func(c *gin.Context) {
		// Simulate a panic
		defer func() {
			if r := recover(); r != nil {
				common.RecordExceptionInSpan(c, "Panic occurred", 
					"panic_value", fmt.Sprintf("%v", r),
					"endpoint", "/test-exception")
				c.JSON(500, gin.H{"error": "Internal server error"})
			}
		}()
		
		// This will cause a panic
		panic("Test panic for exception handling")
	})

	r.GET("/test-error", func(c *gin.Context) {
		// Simulate an error
		err := fmt.Errorf("simulated database connection error")
		common.RecordExceptionWithStack(c, err,
			"component", "database",
			"operation", "connection",
			"endpoint", "/test-error")
		c.JSON(500, gin.H{"error": "Database error"})
	})

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
