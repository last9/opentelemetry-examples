package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/lambda"

	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/crossaccount"
	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/enricher"
)

// clientAdapter bridges crossaccount.ClientFactory to enricher.ClientProvider.
// Both packages define structurally identical TaggingClient interfaces but Go
// requires explicit adaptation between named interface types.
type clientAdapter struct {
	factory *crossaccount.ClientFactory
}

func (a *clientAdapter) GetClient(accountID string) enricher.TaggingClient {
	return a.factory.GetClient(accountID)
}

func (a *clientAdapter) CurrentAccountID() string {
	return a.factory.CurrentAccountID()
}

func main() {
	logger := newLogger(os.Getenv("LOG_LEVEL"))

	// Parse tag cache TTL
	cacheTTL := 1 * time.Hour
	if ttlStr := os.Getenv("TAG_CACHE_TTL"); ttlStr != "" {
		parsed, err := time.ParseDuration(ttlStr)
		if err != nil {
			logger.Error("failed to parse TAG_CACHE_TTL", "error", err)
			os.Exit(1)
		}
		cacheTTL = parsed
	}

	// Initialize cross-account client factory
	factory, err := crossaccount.NewClientFactory(
		context.Background(),
		logger,
		os.Getenv("CROSS_ACCOUNT_ROLES"),
	)
	if err != nil {
		logger.Error("failed to initialize client factory", "error", err)
		os.Exit(1)
	}

	// Build enricher
	tagCache := enricher.NewTagCache(logger, "/tmp/tag-cache", cacheTTL)
	continueOnErr := os.Getenv("CONTINUE_ON_TAG_FAILURE") != "false"

	e := enricher.New(logger, &clientAdapter{factory: factory}, tagCache, enricher.Config{
		ContinueOnError: continueOnErr,
		Region:          os.Getenv("AWS_REGION"),
	})

	handler := NewHandler(logger, e)
	lambda.Start(handler.HandleFirehoseEvent)
}

func newLogger(level string) *slog.Logger {
	logLevel := slog.LevelInfo
	if level == "debug" {
		logLevel = slog.LevelDebug
	}
	return slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: logLevel,
	}))
}
