package main

import (
	"context"
	"encoding/json"
	"gin_example/users"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"
	"gin_example/last9"
	"github.com/uptrace/opentelemetry-go-extra/otelsqlx"
	"github.com/gin-gonic/gin"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq" // PostgreSQL driver
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"github.com/uptrace/opentelemetry-go-extra/otelsql"
)

func main() {
	r := gin.Default()
	i := last9.NewInstrumentation()
	mp, err := last9.InitMetrics()
	if err != nil {
		log.Fatalf("failed to initialize metrics: %v", err)
	}

	// Handle shutdown properly so nothing leaks.
	defer func() {
		if err := mp.Shutdown(context.Background()); err != nil {
			log.Println(err)
		}
	}()

	// Register as global meter provider so that it can be used via otel.Meter
	// and accessed using otel.GetMeterProvider.
	// Most instrumentation libraries use the global meter provider as default.
	// If the global meter provider is not set then a no-op implementation
	// is used, which fails to generate data.
	otel.SetMeterProvider(mp)

	defer func() {
		if err := i.TracerProvider.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Initialize database connection
	db := initDB()
	defer db.Close()

	// Initialize the controller with database connection
	c := users.NewUsersController(db)
	h := users.NewUsersHandler(c, i.Tracer)

	r.Use(otelgin.Middleware("gin-server"))

	// Routes
	r.GET("/users", h.GetUsers)
	r.GET("/users/:id", h.GetUser)
	r.POST("/users", h.CreateUser)
	r.PUT("/users/:id", h.UpdateUser)
	r.DELETE("/users/:id", h.DeleteUser)
	// New route for fetching a random joke
	r.GET("/joke", func(c *gin.Context) {
		getRandomJoke(c, i)
	})

	r.Run()
}

func initDB() *sqlx.DB {
	// Update these connection parameters according to your PostgreSQL configuration
	db, err := otelsqlx.Connect("postgres", "host=localhost port=5432 user=postgres password=postgres sslmode=disable",
	otelsql.WithAttributes(semconv.DBSystemPostgreSQL),
	otelsql.WithDBName("users"))
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}

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

	return db
}

func getRandomJoke(c *gin.Context, i *last9.Instrumentation) {
	// Start a new span for the external API call
	ctx := c.Request.Context()
	ctx, span := i.Tracer.Start(ctx, "get-random-joke")
	defer span.End()

	// Create an HTTP client with OpenTelemetry instrumentation
	client := http.Client{Transport: otelhttp.NewTransport(http.DefaultTransport,
		// By setting the otelhttptrace client in this transport, it can be
		// injected into the context after the span is started, which makes the
		// httptrace spans children of the transport one.
		otelhttp.WithClientTrace(func(ctx context.Context) *httptrace.ClientTrace {
			return otelhttptrace.NewClientTrace(ctx)
		}))}

	// Make a request to the external API
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	resp, err := client.Do(req)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
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

	// Add attributes to the external API call span
	span.SetAttributes(
		attribute.String("joke.setup", joke.Setup),
		attribute.String("joke.punchline", joke.Punchline),
	)

	c.JSON(http.StatusOK, joke)
}
