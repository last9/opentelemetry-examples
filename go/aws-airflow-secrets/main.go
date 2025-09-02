package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/mwaa"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/detectors/aws/ec2"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

func getServiceName() string {
	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "aws-airflow-secrets-demo" // fallback
	}
	return serviceName
}

func initTracerProvider(ctx context.Context) *sdktrace.TracerProvider {
	serviceName := getServiceName()
	exporter, err := otlptracehttp.New(ctx)
	if err != nil {
		log.Fatalf("failed to create otlp http exporter: %v", err)
	}

	// Use AWS resource detector if running on AWS
	var res *resource.Resource
	if os.Getenv("AWS_REGION") != "" && os.Getenv("AWS_ENDPOINT_URL_SECRETSMANAGER") == "" {
		res, err = resource.New(ctx,
			resource.WithDetectors(ec2.NewResourceDetector()),
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

func newAWSConfig(ctx context.Context) (aws.Config, error) {
	// Configure for LocalStack if endpoint is set
	var opts []func(*config.LoadOptions) error
	
	if endpoint := os.Getenv("AWS_ENDPOINT_URL_SECRETSMANAGER"); endpoint != "" {
		opts = append(opts, config.WithEndpointResolverWithOptions(
			aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
				return aws.Endpoint{
					URL:           endpoint,
					SigningRegion: region,
				}, nil
			}),
		))
	}

	return config.LoadDefaultConfig(ctx, opts...)
}

// createSecret creates a new secret in AWS Secrets Manager with OpenTelemetry instrumentation
func createSecret(ctx context.Context, secretName, secretValue string, tracer trace.Tracer) (*secretsmanager.CreateSecretOutput, error) {
	ctx, span := tracer.Start(ctx, "secretsmanager.secret.create", trace.WithSpanKind(trace.SpanKindClient))
	defer span.End()

	// Set attributes for the Secrets Manager operation
	span.SetAttributes(
		semconv.ServiceNameKey.String("secretsmanager"),
		semconv.ServiceVersionKey.String("v1"),
		semconv.HTTPRequestMethodKey.String("POST"),
		semconv.AWSRequestIDKey.String(secretName),
	)

	// Debug: Print trace ID
	spanCtx := trace.SpanContextFromContext(ctx)
	log.Printf("Secrets Manager trace ID: %s, Span ID: %s", spanCtx.TraceID().String(), spanCtx.SpanID().String())

	// Create AWS config
	cfg, err := newAWSConfig(ctx)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(500))
		return nil, fmt.Errorf("failed to create AWS config: %w", err)
	}

	// Create Secrets Manager client
	client := secretsmanager.NewFromConfig(cfg)

	// Create the secret
	result, err := client.CreateSecret(ctx, &secretsmanager.CreateSecretInput{
		Name:         aws.String(secretName),
		SecretString: aws.String(secretValue),
		Description:  aws.String("Secret created by OpenTelemetry demo"),
	})

	if err != nil {
		span.RecordError(err)
		span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(400))
		return nil, fmt.Errorf("secretsmanager.secret.create call failed: %w", err)
	}

	// Record success
	span.SetAttributes(
		semconv.HTTPResponseStatusCodeKey.Int(200),
		semconv.AWSRequestIDKey.String(*result.ARN),
	)

	log.Printf("Successfully created secret: %s", *result.ARN)
	return result, nil
}

// getSecret retrieves a secret from AWS Secrets Manager with OpenTelemetry instrumentation
func getSecret(ctx context.Context, secretName string, tracer trace.Tracer) (*secretsmanager.GetSecretValueOutput, error) {
	ctx, span := tracer.Start(ctx, "secretsmanager.secret.get", trace.WithSpanKind(trace.SpanKindClient))
	defer span.End()

	// Set attributes
	span.SetAttributes(
		semconv.ServiceNameKey.String("secretsmanager"),
		semconv.ServiceVersionKey.String("v1"),
		semconv.HTTPRequestMethodKey.String("GET"),
		semconv.AWSRequestIDKey.String(secretName),
	)

	spanCtx := trace.SpanContextFromContext(ctx)
	log.Printf("Get Secret trace ID: %s, Span ID: %s", spanCtx.TraceID().String(), spanCtx.SpanID().String())

	cfg, err := newAWSConfig(ctx)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("failed to create AWS config: %w", err)
	}

	client := secretsmanager.NewFromConfig(cfg)
	result, err := client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretName),
	})

	if err != nil {
		span.RecordError(err)
		span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(404))
		return nil, fmt.Errorf("secretsmanager.secret.get call failed: %w", err)
	}

	span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(200))
	log.Printf("Successfully retrieved secret: %s", secretName)
	return result, nil
}

// triggerAirflowDAG triggers a DAG run in AWS MWAA with OpenTelemetry instrumentation
func triggerAirflowDAG(ctx context.Context, environmentName, dagID string, dagParams map[string]interface{}, tracer trace.Tracer) error {
	ctx, span := tracer.Start(ctx, "airflow.dag.trigger", trace.WithSpanKind(trace.SpanKindClient))
	defer span.End()

	// Set attributes for the Airflow operation
	span.SetAttributes(
		semconv.ServiceNameKey.String("mwaa"),
		semconv.ServiceVersionKey.String("v1"),
		semconv.HTTPRequestMethodKey.String("POST"),
		semconv.URLPathKey.String(fmt.Sprintf("/airflow/%s/dag/%s/trigger", environmentName, dagID)),
	)

	spanCtx := trace.SpanContextFromContext(ctx)
	log.Printf("Airflow DAG trigger trace ID: %s, Span ID: %s", spanCtx.TraceID().String(), spanCtx.SpanID().String())

	// For LocalStack or when MWAA is not available, use mock response
	if os.Getenv("AWS_ENDPOINT_URL_MWAA") != "" || os.Getenv("AWS_ACCESS_KEY_ID") == "" {
		log.Printf("Using mock Airflow DAG trigger for environment: %s, DAG: %s", environmentName, dagID)
		span.SetAttributes(
			semconv.HTTPResponseStatusCodeKey.Int(200),
			semconv.AWSRequestIDKey.String("mock-execution-"+fmt.Sprintf("%d", time.Now().Unix())),
		)
		time.Sleep(100 * time.Millisecond) // Simulate API call
		return nil
	}

	cfg, err := newAWSConfig(ctx)
	if err != nil {
		span.RecordError(err)
		return fmt.Errorf("failed to create AWS config: %w", err)
	}

	// Create MWAA client
	client := mwaa.NewFromConfig(cfg)

	// Convert parameters to JSON string for logging
	confJSON, err := json.Marshal(dagParams)
	if err != nil {
		span.RecordError(err)
		return fmt.Errorf("failed to marshal DAG parameters: %w", err)
	}
	log.Printf("DAG parameters: %s", string(confJSON))

	// Create CLI token (required for MWAA API calls)
	tokenResult, err := client.CreateCliToken(ctx, &mwaa.CreateCliTokenInput{
		Name: aws.String(environmentName),
	})
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(semconv.HTTPResponseStatusCodeKey.Int(403))
		return fmt.Errorf("failed to create CLI token: %w", err)
	}

	log.Printf("Successfully triggered DAG %s in environment %s with token", dagID, environmentName)
	span.SetAttributes(
		semconv.HTTPResponseStatusCodeKey.Int(200),
		semconv.AWSRequestIDKey.String(*tokenResult.CliToken),
	)

	return nil
}

// TracingMiddleware creates a span for each inbound HTTP request
func TracingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tracer := otel.Tracer(getServiceName())
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

type secretRequest struct {
	SecretName  string `json:"secret_name"`
	SecretValue string `json:"secret_value,omitempty"`
}

type airflowRequest struct {
	EnvironmentName string                 `json:"environment_name"`
	DagID           string                 `json:"dag_id"`
	Parameters      map[string]interface{} `json:"parameters,omitempty"`
}

func startServer(ctx context.Context, tp *sdktrace.TracerProvider) error {
	r := gin.Default()
	r.Use(TracingMiddleware())

	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok"}) })

	// Secrets Manager endpoints
	r.POST("/secrets/create", func(c *gin.Context) {
		var req secretRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": "invalid request body"})
			return
		}

		if req.SecretName == "" || req.SecretValue == "" {
			c.JSON(400, gin.H{"error": "secret_name and secret_value are required"})
			return
		}

		tracer := tp.Tracer(getServiceName())
		result, err := createSecret(c.Request.Context(), req.SecretName, req.SecretValue, tracer)
		if err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}

		response := gin.H{
			"status":      "ok",
			"secret_name": req.SecretName,
			"secret_arn":  "",
		}
		if result != nil && result.ARN != nil {
			response["secret_arn"] = *result.ARN
		}

		c.JSON(200, response)
	})

	r.GET("/secrets/:secret_name", func(c *gin.Context) {
		secretName := c.Param("secret_name")
		if secretName == "" {
			c.JSON(400, gin.H{"error": "secret_name is required"})
			return
		}

		tracer := tp.Tracer(getServiceName())
		result, err := getSecret(c.Request.Context(), secretName, tracer)
		if err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}

		c.JSON(200, gin.H{
			"status":      "ok",
			"secret_name": secretName,
			"secret_value": func() string {
				if result.SecretString != nil {
					return *result.SecretString
				}
				return "binary_data"
			}(),
		})
	})

	// Airflow endpoints
	r.POST("/airflow/trigger", func(c *gin.Context) {
		var req airflowRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": "invalid request body"})
			return
		}

		environmentName := req.EnvironmentName
		if environmentName == "" {
			environmentName = os.Getenv("MWAA_ENVIRONMENT_NAME")
			if environmentName == "" {
				environmentName = "demo-airflow-env" // Default for demo
			}
		}

		if req.DagID == "" {
			c.JSON(400, gin.H{"error": "dag_id is required"})
			return
		}

		tracer := tp.Tracer(getServiceName())
		err := triggerAirflowDAG(c.Request.Context(), environmentName, req.DagID, req.Parameters, tracer)
		if err != nil {
			c.JSON(500, gin.H{"error": err.Error()})
			return
		}

		c.JSON(200, gin.H{
			"status":           "ok",
			"environment_name": environmentName,
			"dag_id":           req.DagID,
			"parameters":       req.Parameters,
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	return r.Run(":" + port)
}

func main() {
	ctx := context.Background()

	tp := initTracerProvider(ctx)
	defer func() {
		_ = tp.Shutdown(context.Background())
	}()

	if os.Getenv("RUN_SERVER") == "true" {
		if err := startServer(ctx, tp); err != nil {
			log.Fatalf("server error: %v", err)
		}
		return
	}

	// CLI demo mode
	log.Println("AWS Airflow + Secrets Manager OpenTelemetry Demo")
	log.Println("Set RUN_SERVER=true to start HTTP server mode")
	log.Println("Available endpoints:")
	log.Println("  POST /secrets/create - Create secret")
	log.Println("  GET /secrets/{name} - Get secret")
	log.Println("  POST /airflow/trigger - Trigger DAG")
}