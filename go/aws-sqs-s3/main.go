package main

import (
    "context"
    "fmt"
    "log"
    "os"
    "strings"
    "time"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "github.com/aws/aws-sdk-go-v2/service/sqs"
    sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
    otelaws "go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/propagation"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
    "go.opentelemetry.io/otel/trace"
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

    res, err := resource.New(ctx,
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
    if err != nil {
        log.Fatalf("failed to create resource: %v", err)
    }

    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exporter),
        sdktrace.WithResource(res),
    )

    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
    return tp
}

func newAWSConfig(ctx context.Context) aws.Config {
    endpoint := os.Getenv("AWS_ENDPOINT_URL")
    if endpoint == "" {
        cfg, err := config.LoadDefaultConfig(ctx)
        if err != nil {
            log.Fatalf("failed to load aws config: %v", err)
        }
        // Enable OTel middleware for all AWS SDK v2 clients
        otelaws.AppendMiddlewares(&cfg.APIOptions)
        return cfg
    }

    resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
        return aws.Endpoint{
            URL:               endpoint,
            HostnameImmutable: true,
        }, nil
    })

    cfg, err := config.LoadDefaultConfig(ctx, config.WithEndpointResolverWithOptions(resolver))
    if err != nil {
        log.Fatalf("failed to load aws config (custom endpoint): %v", err)
    }
    otelaws.AppendMiddlewares(&cfg.APIOptions)
    return cfg
}

func newAWSClients(ctx context.Context) (*s3.Client, *sqs.Client) {
    cfg := newAWSConfig(ctx)
    endpoint := os.Getenv("AWS_ENDPOINT_URL")

    // S3: enable path-style for Localstack-compatible endpoints
    s3Client := s3.NewFromConfig(cfg, func(o *s3.Options) {
        if endpoint != "" {
            o.UsePathStyle = true
        }
    })
    sqsClient := sqs.NewFromConfig(cfg)
    return s3Client, sqsClient
}

// Inject W3C context into SQS MessageAttributes
func injectIntoSQS(ctx context.Context, in *sqs.SendMessageInput) {
    if in.MessageAttributes == nil {
        in.MessageAttributes = map[string]sqstypes.MessageAttributeValue{}
    }
    carrier := propagation.MapCarrier{}
    otel.GetTextMapPropagator().Inject(ctx, carrier)
    for k, v := range carrier {
        in.MessageAttributes[k] = sqstypes.MessageAttributeValue{
            DataType:    aws.String("String"),
            StringValue: aws.String(v),
        }
    }
}

// Extract W3C context from SQS MessageAttributes
func extractFromSQS(ctx context.Context, m sqstypes.Message) context.Context {
    carrier := propagation.MapCarrier{}
    for k, v := range m.MessageAttributes {
        if v.StringValue != nil {
            carrier[k] = aws.ToString(v.StringValue)
        }
    }
    return otel.GetTextMapPropagator().Extract(ctx, carrier)
}

func demo(ctx context.Context, bucket, key, queueURL string, tracer trace.Tracer) error {
    s3c, sqsc := newAWSClients(ctx)

    // S3 PutObject: spans auto-created by otelaws
    _, err := s3c.PutObject(ctx, &s3.PutObjectInput{
        Bucket: aws.String(bucket),
        Key:    aws.String(key),
        Body:   strings.NewReader("hello from otel"),
    })
    if err != nil {
        return fmt.Errorf("s3 put object failed: %w", err)
    }

    // SQS Send: inject trace context for downstream correlation
    send := &sqs.SendMessageInput{
        QueueUrl:    aws.String(queueURL),
        MessageBody: aws.String("work item"),
    }
    injectIntoSQS(ctx, send)
    if _, err = sqsc.SendMessage(ctx, send); err != nil {
        return fmt.Errorf("sqs send failed: %w", err)
    }

    // SQS Receive: request all message attributes so we can extract
    recv, err := sqsc.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
        QueueUrl:              aws.String(queueURL),
        MaxNumberOfMessages:   1,
        WaitTimeSeconds:       5,
        MessageAttributeNames: []string{"All"},
    })
    if err != nil {
        return fmt.Errorf("sqs receive failed: %w", err)
    }

    for _, m := range recv.Messages {
        msgCtx := extractFromSQS(ctx, m)
        msgCtx, span := tracer.Start(msgCtx, "process SQS message", trace.WithSpanKind(trace.SpanKindConsumer))
        // Simulate work
        time.Sleep(50 * time.Millisecond)
        span.End()

        // Delete the message so it is not reprocessed
        _, _ = sqsc.DeleteMessage(ctx, &sqs.DeleteMessageInput{
            QueueUrl:      aws.String(queueURL),
            ReceiptHandle: m.ReceiptHandle,
        })
    }
    return nil
}

func main() {
    ctx := context.Background()

    // Required env
    bucket := mustGetenv("S3_BUCKET")
    key := os.Getenv("S3_KEY")
    if key == "" {
        key = "otel.txt"
    }
    queueURL := mustGetenv("SQS_QUEUE_URL")

    tp := initTracerProvider(ctx, "aws-sqs-s3-demo")
    defer func() {
        // give exporter a moment to flush
        _ = tp.Shutdown(context.Background())
    }()

    tracer := tp.Tracer("aws-sqs-s3-demo")
    rootCtx, span := tracer.Start(ctx, "aws sdk v2 demo")
    if err := demo(rootCtx, bucket, key, queueURL, tracer); err != nil {
        span.RecordError(err)
        span.End()
        log.Fatalf("demo failed: %v", err)
    }
    span.End()
    log.Println("done")
}

