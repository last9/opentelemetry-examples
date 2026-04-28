package main

import (
	"context"
	"crypto/tls"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dbtypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/gin-gonic/gin"
	"github.com/last9/go-agent"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
	"github.com/valkey-io/valkey-go"
	"github.com/valkey-io/valkey-go/valkeyotel"
	otelaws "go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"
)

func newAWSConfig(ctx context.Context) aws.Config {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("aws config: %v", err)
	}

	// Route AWS SDK v2 through OTel middleware. DynamoDBAttributeSetter
	// enriches spans with table name and operation-specific attributes
	// (e.g. aws.dynamodb.table_names) on top of the default RPC attributes.
	otelaws.AppendMiddlewares(
		&cfg.APIOptions,
		otelaws.WithAttributeSetter(otelaws.DynamoDBAttributeSetter),
	)

	// AWS_ENDPOINT_URL supports local testing with amazon/dynamodb-local.
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

	// Options cover every managed + self-hosted deployment we have seen:
	//   - docker-compose / bare metal: defaults (plaintext, no auth)
	//   - AWS ElastiCache / MemoryDB: VALKEY_TLS=true, optional ACL user
	//   - Upstash / Aiven / Redis Cloud: VALKEY_TLS=true + VALKEY_PASSWORD
	// Multiple nodes (cluster / sentinel): comma-separated VALKEY_ADDR.
	opt := valkey.ClientOption{
		InitAddress: strings.Split(addr, ","),
		Username:    os.Getenv("VALKEY_USERNAME"),
		Password:    os.Getenv("VALKEY_PASSWORD"),
	}
	if os.Getenv("VALKEY_TLS") == "true" {
		opt.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}

	// valkeyotel.NewClient constructs an instrumented valkey client in a
	// single call. It returns (valkey.Client, error) — no separate wrap step.
	client, err := valkeyotel.NewClient(opt)
	if err != nil {
		log.Fatalf("valkey: %v", err)
	}
	return client
}

func main() {
	ctx := context.Background()

	if err := agent.Start(); err != nil {
		log.Fatalf("go-agent: %v", err)
	}
	defer agent.Shutdown()

	awsCfg := newAWSConfig(ctx)
	dynClient := dynamodb.NewFromConfig(awsCfg)

	valkeyClient := newValkeyClient()
	defer valkeyClient.Close()

	table := os.Getenv("DYNAMODB_TABLE")
	if table == "" {
		table = "users"
	}

	r := ginagent.Default()

	// GET /users/:id — DynamoDB GetItem.
	// c.Request.Context() propagates the HTTP server span so the DynamoDB
	// span appears as its child in Last9 Trace Explorer.
	r.GET("/users/:id", func(c *gin.Context) {
		out, err := dynClient.GetItem(c.Request.Context(), &dynamodb.GetItemInput{
			TableName: aws.String(table),
			Key: map[string]dbtypes.AttributeValue{
				"user_id": &dbtypes.AttributeValueMemberS{Value: c.Param("id")},
			},
		})
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if out.Item == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"item": out.Item})
	})

	// GET /cache/:key — Valkey GET.
	r.GET("/cache/:key", func(c *gin.Context) {
		val, err := valkeyClient.Do(c.Request.Context(),
			valkeyClient.B().Get().Key(c.Param("key")).Build(),
		).ToString()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"key": c.Param("key"), "value": val})
	})

	// POST /cache/:key — Valkey SET, used to seed keys during local testing.
	r.POST("/cache/:key", func(c *gin.Context) {
		value := c.Query("value")
		if value == "" {
			value = "hello"
		}
		if err := valkeyClient.Do(c.Request.Context(),
			valkeyClient.B().Set().Key(c.Param("key")).Value(value).Build(),
		).Error(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"key": c.Param("key"), "value": value})
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("listening on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}
