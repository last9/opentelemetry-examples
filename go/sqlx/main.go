package main

import (
	"encoding/json"
	"gin_example/users"
	"io"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"
	"github.com/last9/go-agent"
	dbagent "github.com/last9/go-agent/integrations/database"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
	httpagent "github.com/last9/go-agent/integrations/http"
	_ "github.com/lib/pq" // PostgreSQL driver
)

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	// Initialize database connection with go-agent
	db := initDB()
	defer db.Close()

	// Initialize the controller with database connection
	c := users.NewUsersController(db)
	h := users.NewUsersHandler(c)

	// Create Gin router with go-agent instrumentation
	r := ginagent.Default()

	// Routes
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)
	r.GET("/joke", getRandomJoke)

	log.Println("✓ Gin server running on :8080 (instrumented by go-agent)")
	r.Run()
}

func initDB() *sqlx.DB {
	// Open database with go-agent (automatic instrumentation)
	sqlDB, err := dbagent.Open(dbagent.Config{
		DriverName:   "postgres",
		DSN:          "host=localhost port=5432 user=postgres password=your-password-here sslmode=disable",
		DatabaseName: "users",
	})
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}

	// Wrap with sqlx
	db := sqlx.NewDb(sqlDB, "postgres")

	// Create users table if it doesn't exist
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id VARCHAR(36) PRIMARY KEY,
		name VARCHAR(100) NOT NULL,
		email VARCHAR(100) NOT NULL UNIQUE
	);`

	_, err = db.Exec(schema)
	if err != nil {
		log.Fatalf("failed to create users table: %v", err)
	}

	log.Println("✓ sqlx database connected with go-agent instrumentation")
	return db
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
