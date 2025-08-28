package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/pubsub"
	"cloud.google.com/go/storage"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/detectors/gcp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/api/option"
)

func mustGetenv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("missing required env: %s", key)
	}
	return v
}

func initTracerProvider(ctx context.Context, serviceName string) *sdktrace.TracerProvider {
	exporter, err := otlptracehttp.New(ctx)
	if err != nil {
		log.Fatalf("failed to create otlp http exporter: %v", err)
	}

	// Use GCP resource detector if running on GCP, otherwise fallback to basic resource
	var res *resource.Resource
	if os.Getenv("GOOGLE_CLOUD_PROJECT") != "" && os.Getenv("STORAGE_EMULATOR_HOST") == "" {
		res, err = resource.New(ctx,
			resource.WithDetectors(gcp.NewDetector()),
			resource.WithFromEnv(),
			resource.WithTelemetrySDK(),
			resource.WithProcess(),
			resource.WithOS(),
			resource.WithContainer(),
			resource.WithHost(),
			resource.WithAttributes(
				semconv.ServiceNameKey.String(serviceName),
			),
		)
	} else {
		res, err = resource.New(ctx,
			resource.WithFromEnv(),
			resource.WithTelemetrySDK(),
			resource.WithProcess(),
			resource.WithOS(),
			resource.WithContainer(),
			resource.WithHost(),
			resource.WithAttributes(
				semconv.ServiceNameKey.String(serviceName),
			),
		)
	}
	if err != nil {
		log.Fatalf("failed to create resource: %v", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
	return tp
}

func newGCPClients(ctx context.Context) (*storage.Client, *pubsub.Client) {
	var opts []option.ClientOption

	// Configure for emulator endpoints if set
	if storageHost := os.Getenv("STORAGE_EMULATOR_HOST"); storageHost != "" {
		opts = append(opts, option.WithEndpoint("http://"+storageHost+"/storage/v1/"))
		opts = append(opts, option.WithoutAuthentication())
	}

	storageClient, err := storage.NewClient(ctx, opts...)
	if err != nil {
		log.Fatalf("failed to create storage client: %v", err)
	}

	// For Pub/Sub, use separate options since it needs different endpoints
	var pubsubOpts []option.ClientOption

	if pubsubHost := os.Getenv("PUBSUB_EMULATOR_HOST"); pubsubHost != "" {
		pubsubOpts = append(pubsubOpts, option.WithEndpoint(pubsubHost))
		pubsubOpts = append(pubsubOpts, option.WithoutAuthentication())
	}

	projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
	if projectID == "" {
		projectID = "demo-project"
	}

	pubsubClient, err := pubsub.NewClient(ctx, projectID, pubsubOpts...)
	if err != nil {
		log.Fatalf("failed to create pubsub client: %v", err)
	}

	return storageClient, pubsubClient
}

// Inject W3C context into Pub/Sub message attributes
func injectIntoPubSub(ctx context.Context, msg *pubsub.Message) {
	if msg.Attributes == nil {
		msg.Attributes = map[string]string{}
	}
	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	for k, v := range carrier {
		msg.Attributes[k] = v
	}
}

// Extract W3C context from Pub/Sub message attributes
func extractFromPubSub(ctx context.Context, msg *pubsub.Message) context.Context {
	carrier := propagation.MapCarrier{}
	for k, v := range msg.Attributes {
		carrier[k] = v
	}
	return otel.GetTextMapPropagator().Extract(ctx, carrier)
}

func demo(ctx context.Context, bucket, objectName, topicName, subscriptionName string, tracer trace.Tracer) error {
	storageClient, pubsubClient := newGCPClients(ctx)
	defer storageClient.Close()
	defer pubsubClient.Close()

	// Cloud Storage: Upload object with manual span for proper nesting
	storageCtx, storageSpan := tracer.Start(ctx, "upload object to GCS", trace.WithSpanKind(trace.SpanKindClient))
	storageSpan.SetAttributes(
		semconv.CloudResourceIDKey.String(bucket+"/"+objectName),
	)
	
	// Debug: Print trace ID for storage span
	storageSpanCtx := trace.SpanContextFromContext(storageCtx)
	log.Printf("Storage trace ID: %s, Span ID: %s", storageSpanCtx.TraceID().String(), storageSpanCtx.SpanID().String())
	
	bucketHandle := storageClient.Bucket(bucket)
	objectHandle := bucketHandle.Object(objectName)
	
	writer := objectHandle.NewWriter(storageCtx)
	if _, err := writer.Write([]byte("hello from otel gcp example")); err != nil {
		writer.Close()
		storageSpan.RecordError(err)
		storageSpan.End()
		return fmt.Errorf("storage write failed: %w", err)
	}
	if err := writer.Close(); err != nil {
		storageSpan.RecordError(err)
		storageSpan.End()
		return fmt.Errorf("storage close failed: %w", err)
	}
	storageSpan.End()

	// Pub/Sub Publish: inject trace context for downstream correlation
	publishCtx, publishSpan := tracer.Start(ctx, "publish message to Pub/Sub", trace.WithSpanKind(trace.SpanKindProducer))
	publishSpan.SetAttributes(
		semconv.MessagingDestinationNameKey.String(topicName),
		semconv.MessagingSystemKey.String("pubsub"),
	)
	
	topic := pubsubClient.Topic(topicName)
	msg := &pubsub.Message{
		Data: []byte("work item from storage upload"),
	}
	injectIntoPubSub(publishCtx, msg)
	
	result := topic.Publish(publishCtx, msg)
	if _, err := result.Get(publishCtx); err != nil {
		publishSpan.RecordError(err)
		publishSpan.End()
		return fmt.Errorf("pubsub publish failed: %w", err)
	}
	publishSpan.End()

	// Pub/Sub Subscribe: receive message and extract context
	subscribeCtx, subscribeSpan := tracer.Start(ctx, "receive message from Pub/Sub", trace.WithSpanKind(trace.SpanKindConsumer))
	subscribeSpan.SetAttributes(
		semconv.MessagingDestinationNameKey.String(subscriptionName),
		semconv.MessagingSystemKey.String("pubsub"),
	)
	
	subscription := pubsubClient.Subscription(subscriptionName)
	
	// Use a timeout context for receiving
	receiveCtx, cancel := context.WithTimeout(subscribeCtx, 10*time.Second)
	defer cancel()

	err := subscription.Receive(receiveCtx, func(ctx context.Context, msg *pubsub.Message) {
		// Extract trace context from message
		msgCtx := extractFromPubSub(ctx, msg)
		msgCtx, span := tracer.Start(msgCtx, "process Pub/Sub message", trace.WithSpanKind(trace.SpanKindConsumer))
		
		// Simulate work
		time.Sleep(50 * time.Millisecond)
		span.End()
		
		// Acknowledge the message
		msg.Ack()
	})

	if err != nil && !strings.Contains(err.Error(), "context deadline exceeded") {
		subscribeSpan.RecordError(err)
		subscribeSpan.End()
		return fmt.Errorf("pubsub receive failed: %w", err)
	}
	subscribeSpan.End()

	return nil
}

// TracingMiddleware creates a span for each inbound HTTP request
func TracingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tracer := otel.Tracer("gcp-pubsub-storage-demo")
		spanName := fmt.Sprintf("%s %s", c.Request.Method, c.Request.URL.Path)

		ctx, span := tracer.Start(
			c.Request.Context(),
			spanName,
			trace.WithSpanKind(trace.SpanKindServer),
		)
		defer span.End()

		c.Request = c.Request.WithContext(ctx)

		start := time.Now()
		c.Next()

		span.SetAttributes(
			semconv.HTTPRequestMethodKey.String(c.Request.Method),
			semconv.URLFull(c.Request.URL.String()),
			semconv.UserAgentOriginal(c.Request.UserAgent()),
		)
		span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(c.Writer.Status()))
		_ = start
	}
}

type demoRequest struct {
	Bucket           string `json:"bucket"`
	ObjectName       string `json:"object_name"`
	TopicName        string `json:"topic_name"`
	SubscriptionName string `json:"subscription_name"`
}

func startServer(ctx context.Context, tp *sdktrace.TracerProvider) error {
	r := gin.Default()
	r.Use(TracingMiddleware())

	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })

	r.POST("/demo", func(c *gin.Context) {
		var req demoRequest
		_ = c.ShouldBindJSON(&req)

		bucket := req.Bucket
		if bucket == "" {
			bucket = os.Getenv("GCS_BUCKET")
		}
		if bucket == "" {
			c.JSON(400, gin.H{"error": "missing bucket (json bucket or env GCS_BUCKET)"})
			return
		}

		objectName := req.ObjectName
		if objectName == "" {
			objectName = os.Getenv("GCS_OBJECT_NAME")
			if objectName == "" {
				objectName = "otel.txt"
			}
		}

		topicName := req.TopicName
		if topicName == "" {
			topicName = os.Getenv("PUBSUB_TOPIC")
		}
		if topicName == "" {
			c.JSON(400, gin.H{"error": "missing topic_name (json topic_name or env PUBSUB_TOPIC)"})
			return
		}

		subscriptionName := req.SubscriptionName
		if subscriptionName == "" {
			subscriptionName = os.Getenv("PUBSUB_SUBSCRIPTION")
		}
		if subscriptionName == "" {
			c.JSON(400, gin.H{"error": "missing subscription_name (json subscription_name or env PUBSUB_SUBSCRIPTION)"})
			return
		}

		// Create resources dynamically for the API request
		if err := createEmulatorResources(c.Request.Context(), bucket, topicName, subscriptionName); err != nil {
			c.JSON(500, gin.H{"error": fmt.Sprintf("failed to create emulator resources: %v", err)})
			return
		}

		tracer := tp.Tracer("gcp-pubsub-storage-demo")
		if err := demo(c.Request.Context(), bucket, objectName, topicName, subscriptionName, tracer); err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}
		c.JSON(200, gin.H{
			"status":            "ok",
			"bucket":            bucket,
			"object_name":       objectName,
			"topic_name":        topicName,
			"subscription_name": subscriptionName,
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	return r.Run(":" + port)
}

func createEmulatorResources(ctx context.Context, bucket, topicName, subscriptionName string) error {
	if bucket == "" || topicName == "" || subscriptionName == "" {
		return nil // Skip setup if parameters are empty
	}

	storageClient, pubsubClient := newGCPClients(ctx)
	defer storageClient.Close()
	defer pubsubClient.Close()

	// Create bucket if using emulator
	if os.Getenv("STORAGE_EMULATOR_HOST") != "" {
		if err := storageClient.Bucket(bucket).Create(ctx, "demo-project", nil); err != nil {
			log.Printf("bucket creation failed (might already exist): %v", err)
		}
	}

	// Create topic and subscription if using emulator
	if os.Getenv("PUBSUB_EMULATOR_HOST") != "" {
		topic := pubsubClient.Topic(topicName)
		if exists, err := topic.Exists(ctx); err != nil {
			return fmt.Errorf("failed to check topic existence: %w", err)
		} else if !exists {
			if _, err := pubsubClient.CreateTopic(ctx, topicName); err != nil {
				return fmt.Errorf("failed to create topic: %w", err)
			}
		}

		subscription := pubsubClient.Subscription(subscriptionName)
		if exists, err := subscription.Exists(ctx); err != nil {
			return fmt.Errorf("failed to check subscription existence: %w", err)
		} else if !exists {
			if _, err := pubsubClient.CreateSubscription(ctx, subscriptionName, pubsub.SubscriptionConfig{
				Topic: topic,
			}); err != nil {
				return fmt.Errorf("failed to create subscription: %w", err)
			}
		}
	}

	return nil
}

func setupEmulatorResources(ctx context.Context) error {
	bucket := os.Getenv("GCS_BUCKET")
	topicName := os.Getenv("PUBSUB_TOPIC")
	subscriptionName := os.Getenv("PUBSUB_SUBSCRIPTION")

	return createEmulatorResources(ctx, bucket, topicName, subscriptionName)
}

func main() {
	ctx := context.Background()

	tp := initTracerProvider(ctx, "gcp-pubsub-storage-demo")
	defer func() {
		_ = tp.Shutdown(context.Background())
	}()

	// Setup emulator resources if needed
	if err := setupEmulatorResources(ctx); err != nil {
		log.Printf("emulator setup failed: %v", err)
	}

	if os.Getenv("RUN_SERVER") == "true" {
		if err := startServer(ctx, tp); err != nil {
			log.Fatalf("server error: %v", err)
		}
		return
	}

	// One-shot CLI demo mode
	bucket := mustGetenv("GCS_BUCKET")
	objectName := os.Getenv("GCS_OBJECT_NAME")
	if objectName == "" {
		objectName = "otel.txt"
	}
	topicName := mustGetenv("PUBSUB_TOPIC")
	subscriptionName := mustGetenv("PUBSUB_SUBSCRIPTION")

	tracer := tp.Tracer("gcp-pubsub-storage-demo")
	rootCtx, span := tracer.Start(ctx, "gcp cloud client demo")
	
	// Debug: Print trace ID
	spanCtx := trace.SpanContextFromContext(rootCtx)
	log.Printf("Root trace ID: %s, Span ID: %s", spanCtx.TraceID().String(), spanCtx.SpanID().String())
	
	if err := demo(rootCtx, bucket, objectName, topicName, subscriptionName, tracer); err != nil {
		span.RecordError(err)
		span.End()
		log.Fatalf("demo failed: %v", err)
	}
	span.End()
	log.Println("done")
}