package main

import (
	"context"
	"crypto/tls"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dbtypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/gin-gonic/gin"
	"github.com/last9/go-agent"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
	httpagent "github.com/last9/go-agent/integrations/http"
	"github.com/valkey-io/valkey-go"
	"github.com/valkey-io/valkey-go/valkeyotel"
	otelaws "go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// tracer is package-global. The context.Context is NEVER cached on a struct —
// it is passed as the first argument to every method. Caching ctx at boot
// time is the most common cause of orphan span trees in Last9.
var tracer = otel.Tracer("gin-dynamodb-valkey")

// Service holds long-lived dependencies (clients, table names). It does NOT
// hold a context.Context. Every method takes ctx as its first parameter so
// the request-scoped span context flows through unchanged.
type Service struct {
	dyn    *dynamodb.Client
	valkey valkey.Client
	http   *http.Client
	table  string
}

// GetUser fetches an item from DynamoDB. The custom internal span nests under
// the gin SERVER span because we receive ctx from the handler and pass it
// to dynClient.GetItem — otelaws picks up the parent automatically.
func (s *Service) GetUser(ctx context.Context, id string) (map[string]dbtypes.AttributeValue, error) {
	ctx, span := tracer.Start(ctx, "Service.GetUser")
	defer span.End()
	span.SetAttributes(attribute.String("user.id", id))

	out, err := s.dyn.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.table),
		Key: map[string]dbtypes.AttributeValue{
			"user_id": &dbtypes.AttributeValueMemberS{Value: id},
		},
	})
	if err != nil {
		span.RecordError(err)
		return nil, err
	}
	return out.Item, nil
}

// CacheGet reads a key from Valkey. Same ctx propagation rule.
func (s *Service) CacheGet(ctx context.Context, key string) (string, error) {
	ctx, span := tracer.Start(ctx, "Service.CacheGet")
	defer span.End()
	return s.valkey.Do(ctx, s.valkey.B().Get().Key(key).Build()).ToString()
}

// CacheSet writes a key to Valkey.
func (s *Service) CacheSet(ctx context.Context, key, value string) error {
	ctx, span := tracer.Start(ctx, "Service.CacheSet")
	defer span.End()
	return s.valkey.Do(ctx, s.valkey.B().Set().Key(key).Value(value).Build()).Error()
}

// CallExternal demonstrates outbound HTTP with trace-context propagation.
// httpagent.NewClient does two things: (1) emits a CLIENT span nested under
// ctx, (2) injects the W3C traceparent header so the receiving service joins
// this trace. A bare http.Client emits orphan spans AND breaks cross-service
// correlation.
func (s *Service) CallExternal(ctx context.Context, url string) (int, error) {
	ctx, span := tracer.Start(ctx, "Service.CallExternal")
	defer span.End()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		span.RecordError(err)
		return 0, err
	}
	resp, err := s.http.Do(req)
	if err != nil {
		span.RecordError(err)
		return 0, err
	}
	defer resp.Body.Close()
	span.SetAttributes(attribute.Int("http.response.status_code", resp.StatusCode))
	return resp.StatusCode, nil
}

// SQSPoller runs a long-poll receive loop. Background pollers have no inbound
// request, so each iteration explicitly starts a NEW ROOT span — the receive
// + per-message processing form one logical trace per batch.
type SQSPoller struct {
	client   *sqs.Client
	queueURL string
	handler  func(ctx context.Context, body string) error
}

// Run blocks until ctx is cancelled. The ctx passed in MUST NOT have a timeout
// shorter than WaitTimeSeconds (20s here) — otherwise every ReceiveMessage is
// cancelled mid-flight and recorded as STATUS_CODE_ERROR.
func (p *SQSPoller) Run(ctx context.Context) {
	for {
		if ctx.Err() != nil {
			return
		}
		p.poll(ctx)
	}
}

func (p *SQSPoller) poll(parent context.Context) {
	ctx, span := tracer.Start(parent, "sqs.poll", trace.WithNewRoot())
	defer span.End()

	out, err := p.client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(p.queueURL),
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     20,
	})
	if err != nil {
		span.RecordError(err)
		return
	}
	span.SetAttributes(attribute.Int("messaging.batch.message_count", len(out.Messages)))

	for _, msg := range out.Messages {
		if err := p.handler(ctx, aws.ToString(msg.Body)); err != nil {
			span.RecordError(err)
			continue
		}
		_, _ = p.client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
			QueueUrl:      aws.String(p.queueURL),
			ReceiptHandle: msg.ReceiptHandle,
		})
	}
}

func newAWSConfig(ctx context.Context) aws.Config {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("aws config: %v", err)
	}

	// Register otelaws BEFORE building any service client. Middleware on the
	// config flows into every client built from it. DynamoDBAttributeSetter
	// adds aws.dynamodb.table_names + operation-specific attributes.
	otelaws.AppendMiddlewares(
		&cfg.APIOptions,
		otelaws.WithAttributeSetter(otelaws.DynamoDBAttributeSetter),
	)

	if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
		cfg.BaseEndpoint = aws.String(endpoint)
	}
	return cfg
}

func newValkeyClient() valkey.Client {
	addr := os.Getenv("VALKEY_ADDR")
	if addr == "" {
		addr = "localhost:6379"
	}
	opt := valkey.ClientOption{
		InitAddress: strings.Split(addr, ","),
		Username:    os.Getenv("VALKEY_USERNAME"),
		Password:    os.Getenv("VALKEY_PASSWORD"),
	}
	if os.Getenv("VALKEY_TLS") == "true" {
		opt.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	client, err := valkeyotel.NewClient(opt)
	if err != nil {
		log.Fatalf("valkey: %v", err)
	}
	return client
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := agent.Start(); err != nil {
		log.Fatalf("go-agent: %v", err)
	}
	defer agent.Shutdown()

	awsCfg := newAWSConfig(ctx)
	svc := &Service{
		dyn:    dynamodb.NewFromConfig(awsCfg),
		valkey: newValkeyClient(),
		// httpagent.NewClient wraps the transport with trace-context injection
		// + automatic CLIENT span emission for every outbound request.
		http:  httpagent.NewClient(&http.Client{Timeout: 10 * time.Second}),
		table: getenv("DYNAMODB_TABLE", "users"),
	}
	defer svc.valkey.Close()

	// Optional SQS poller — runs only when SQS_QUEUE_URL is set.
	if queueURL := os.Getenv("SQS_QUEUE_URL"); queueURL != "" {
		poller := &SQSPoller{
			client:   sqs.NewFromConfig(awsCfg),
			queueURL: queueURL,
			handler: func(ctx context.Context, body string) error {
				_, span := tracer.Start(ctx, "process.message")
				defer span.End()
				span.SetAttributes(attribute.Int("message.length", len(body)))
				return nil
			},
		}
		go poller.Run(ctx)
	}

	r := ginagent.Default()

	// Every handler converts *gin.Context to c.Request.Context() once, then
	// passes that ctx down through the service layer. Service methods take
	// ctx as first arg — never read from a struct field.
	r.GET("/users/:id", func(c *gin.Context) {
		item, err := svc.GetUser(c.Request.Context(), c.Param("id"))
		switch {
		case errors.Is(err, nil) && item == nil:
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		case err != nil:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		default:
			c.JSON(http.StatusOK, gin.H{"item": item})
		}
	})

	r.GET("/cache/:key", func(c *gin.Context) {
		val, err := svc.CacheGet(c.Request.Context(), c.Param("key"))
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"key": c.Param("key"), "value": val})
	})

	r.POST("/cache/:key", func(c *gin.Context) {
		value := c.Query("value")
		if value == "" {
			value = "hello"
		}
		if err := svc.CacheSet(c.Request.Context(), c.Param("key"), value); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"key": c.Param("key"), "value": value})
	})

	// Demonstrates outbound HTTP. The CLIENT span emitted by httpagent nests
	// under the SERVER span; traceparent is injected so the receiver joins
	// the same trace.
	r.GET("/external", func(c *gin.Context) {
		target := c.DefaultQuery("url", "https://httpbin.org/get")
		status, err := svc.CallExternal(c.Request.Context(), target)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": status})
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	srv := &http.Server{Addr: ":" + getenv("PORT", "8080"), Handler: r}
	go func() {
		log.Printf("listening on %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()

	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdown)
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
