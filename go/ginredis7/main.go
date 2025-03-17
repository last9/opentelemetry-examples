package main

import (
	"context"
	"encoding/json"
	"fmt"
	"gin_example/last9"
	"gin_example/users"
	"io"
	"log"
	"net/http"
	"net/http/httptrace"
	"os"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/go-redis/redis/v7"
	"github.com/google/uuid"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

type JobStatus string

const (
	JobStatusPending  JobStatus = "pending"
	JobStatusComplete JobStatus = "complete"
	JobStatusFailed   JobStatus = "failed"
)

type Job struct {
	ID          string      `json:"id"`
	Type        string      `json:"type"`
	Payload     interface{} `json:"payload"`
	Status      JobStatus   `json:"status"`
	CreatedAt   time.Time   `json:"created_at"`
	CompletedAt *time.Time  `json:"completed_at,omitempty"`
	Error       string      `json:"error,omitempty"`
}

type JobHandler func(context.Context, *Job) error

type JobProcessor struct {
	broker   last9.MessageBroker
	handlers map[string]JobHandler
}

func NewJobProcessor(broker last9.MessageBroker) *JobProcessor {
	return &JobProcessor{
		broker:   broker,
		handlers: make(map[string]JobHandler),
	}
}

func (p *JobProcessor) RegisterHandler(jobType string, handler JobHandler) {
	p.handlers[jobType] = handler
}

func (p *JobProcessor) PublishJob(ctx context.Context, queueName string, jobType string, payload interface{}) (*Job, error) {
	// Create new job
	job := &Job{
		ID:        uuid.New().String(),
		Type:      jobType,
		Payload:   payload,
		Status:    JobStatusPending,
		CreatedAt: time.Now(),
	}

	// Marshal job to JSON
	jobBytes, err := json.Marshal(job)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal job: %v", err)
	}

	// Publish the message
	err = p.broker.PublishMessage(ctx, queueName, jobBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to publish job: %v", err)
	}

	return job, nil
}

func (p *JobProcessor) StartConsumer(ctx context.Context, queueName string) error {
	msgs, err := p.broker.ConsumeMessages(ctx, queueName)
	if err != nil {
		return fmt.Errorf("failed to start consumer: %v", err)
	}

	go func() {
		for msg := range msgs {
			// Use the context from the message instead of the parent context
			jobCtx, jobSpan := otel.Tracer("job-processor").Start(msg.Context, "process.job",
				trace.WithAttributes(
					attribute.String("messaging.system", "rabbitmq"),
					attribute.String("messaging.destination", queueName),
					attribute.String("messaging.destination_kind", "queue"),
					attribute.String("messaging.operation", "process"),
					attribute.String("messaging.message_id", msg.Original.MessageId),
					attribute.String("messaging.conversation_id", msg.Original.CorrelationId),
				))

			var job Job
			if err := json.Unmarshal(msg.Body, &job); err != nil {
				jobSpan.RecordError(err)
				jobSpan.SetStatus(codes.Error, "failed to unmarshal job")
				p.broker.NackMessage(jobCtx, msg.Original, false)
				jobSpan.End()
				continue
			}

			jobSpan.SetAttributes(
				attribute.String("job.id", job.ID),
				attribute.String("job.type", job.Type),
				attribute.String("job.status", string(job.Status)),
			)

			if handler, ok := p.handlers[job.Type]; ok {
				// Create handler span as child of job span
				handlerCtx, handlerSpan := otel.Tracer("job-processor").Start(jobCtx, "execute.handler",
					trace.WithAttributes(
						attribute.String("job.id", job.ID),
						attribute.String("job.type", job.Type),
						attribute.String("messaging.system", "rabbitmq"),
						attribute.String("messaging.destination", queueName),
						attribute.String("messaging.destination_kind", "queue"),
						attribute.String("messaging.operation", "process"),
						attribute.String("messaging.message_id", msg.Original.MessageId),
						attribute.String("messaging.conversation_id", msg.Original.CorrelationId),
					))

				err := handler(handlerCtx, &job)
				if err != nil {
					handlerSpan.RecordError(err)
					handlerSpan.SetStatus(codes.Error, err.Error())
					log.Printf("Failed to process job %s: %v", job.ID, err)
					job.Status = JobStatusFailed
					job.Error = err.Error()
					// Use handlerCtx for NackMessage to make it a child of handler span
					p.broker.NackMessage(handlerCtx, msg.Original, false)
				} else {
					now := time.Now()
					job.Status = JobStatusComplete
					job.CompletedAt = &now
					handlerSpan.SetStatus(codes.Ok, "job completed successfully")
					// Use handlerCtx for AckMessage to make it a child of handler span
					p.broker.AckMessage(handlerCtx, msg.Original)
				}
				handlerSpan.End()
			} else {
				err := fmt.Errorf("no handler for job type: %s", job.Type)
				jobSpan.RecordError(err)
				jobSpan.SetStatus(codes.Error, err.Error())
				log.Printf("No handler for job type: %s", job.Type)
				p.broker.NackMessage(jobCtx, msg.Original, false)
			}

			jobSpan.End()
		}
	}()

	return nil
}

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

	// Initialize Redis client
	redisClient := initRedis()

	// Initialize the controller with Redis client
	c := users.NewUsersController(redisClient)
	h := users.NewUsersHandler(c, i.Tracer)

	// Initialize RabbitMQ broker
	rmqConfig := &last9.RabbitMQConfig{
		Host:     getEnv("RABBITMQ_HOST", "localhost"),
		Port:     getEnv("RABBITMQ_PORT", "5672"),
		Username: getEnv("RABBITMQ_USER", "myuser"),
		Password: getEnv("RABBITMQ_PASS", "mypassword"),
		VHost:    getEnv("RABBITMQ_VHOST", "/"),
	}

	rmqBroker, err := last9.NewRabbitMQBroker(rmqConfig, i.Tracer)
	if err != nil {
		log.Fatalf("Failed to initialize RabbitMQ broker: %v", err)
	}
	defer rmqBroker.Close()

	// Initialize job processor with the broker
	jobProcessor := NewJobProcessor(rmqBroker)

	// Register handlers
	jobProcessor.RegisterHandler("email", func(ctx context.Context, job *Job) error {
		// Simulate email processing
		time.Sleep(time.Second)

		log.Println("processing job")
		payload, ok := job.Payload.(map[string]interface{})
		if !ok {
			return fmt.Errorf("invalid payload type")
		}

		log.Printf("Sending email to %v: %v", payload["to"], payload["subject"])
		return nil
	})

	// Start the consumer
	err = jobProcessor.StartConsumer(context.Background(), "email_queue")
	if err != nil {
		log.Fatalf("Failed to start job consumer: %v", err)
	}

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

	// Add a route for submitting email jobs
	r.POST("/send-email", func(c *gin.Context) {
		payload := map[string]interface{}{
			"to":      "admin@example.com",
			"subject": "test subject",
			"body":    "test body",
		}

		job, err := jobProcessor.PublishJob(c.Request.Context(), "email_queue", "email", payload)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusAccepted, gin.H{
			"job_id": job.ID,
			"status": job.Status,
		})
	})

	r.Run()
}

func initRedis() *redis.Client {
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379", // Update this with your Redis server address
	})
	// Add OpenTelemetry hook
	rdb.AddHook(last9.NewOtelHook("redis-client"))
	return rdb
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

// Helper function to get environment variables with default values
func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}
