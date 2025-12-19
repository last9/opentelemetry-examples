package external

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type Client struct {
	httpClient *http.Client
	baseURL    string
}

// Quote represents an inspirational quote from the API
type Quote struct {
	Content string `json:"content"`
	Author  string `json:"author"`
}

// UserInfo represents enriched user information from external service
type UserInfo struct {
	Name        string    `json:"name"`
	Location    string    `json:"location"`
	Timezone    string    `json:"timezone"`
	LastActive  time.Time `json:"last_active"`
	MemberSince time.Time `json:"member_since"`
}

// NewClient creates a new external API client with OTel instrumentation
func NewClient(baseURL string) *Client {
	return &Client{
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
			Transport: otelhttp.NewTransport(
				http.DefaultTransport,
				otelhttp.WithSpanNameFormatter(func(operation string, r *http.Request) string {
					return fmt.Sprintf("HTTP %s %s", r.Method, r.URL.Path)
				}),
			),
		},
		baseURL: baseURL,
	}
}

// GetInspirationalQuote fetches a random inspirational quote
// This simulates calling an external API service
func (c *Client) GetInspirationalQuote(ctx context.Context) (*Quote, error) {
	tracer := otel.Tracer("external-api-client")
	ctx, span := tracer.Start(ctx, "GetInspirationalQuote",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("external.service", "quotable"),
			attribute.String("external.operation", "get_random_quote"),
		),
	)
	defer span.End()

	// Use a real public API for quotes
	req, err := http.NewRequestWithContext(ctx, "GET", "https://api.quotable.io/random", nil)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("failed to fetch quote: %w", err)
	}
	defer resp.Body.Close()

	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.String("http.response.content_type", resp.Header.Get("Content-Type")),
	)

	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf("unexpected status code: %d", resp.StatusCode)
		span.RecordError(err)
		return nil, err
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var quote Quote
	if err := json.Unmarshal(body, &quote); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("failed to parse quote: %w", err)
	}

	span.SetAttributes(
		attribute.String("quote.author", quote.Author),
		attribute.Int("quote.length", len(quote.Content)),
	)

	return &quote, nil
}

// EnrichUserInfo simulates fetching additional user information from an external service
func (c *Client) EnrichUserInfo(ctx context.Context, name string) (*UserInfo, error) {
	tracer := otel.Tracer("external-api-client")
	ctx, span := tracer.Start(ctx, "EnrichUserInfo",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("external.service", "user-enrichment"),
			attribute.String("user.name", name),
		),
	)
	defer span.End()

	// Simulate external API call with some processing time
	time.Sleep(50 * time.Millisecond)

	// Simulate enriched data (in real world, this would be an actual API call)
	locations := []string{"San Francisco", "New York", "London", "Tokyo", "Berlin", "Sydney"}
	timezones := []string{"America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo", "Europe/Berlin", "Australia/Sydney"}

	// Use name hash to get consistent location for same user
	hash := 0
	for _, c := range name {
		hash += int(c)
	}
	locationIdx := hash % len(locations)

	userInfo := &UserInfo{
		Name:        name,
		Location:    locations[locationIdx],
		Timezone:    timezones[locationIdx],
		LastActive:  time.Now().Add(-time.Duration(hash%24) * time.Hour),
		MemberSince: time.Now().Add(-time.Duration(hash%365) * 24 * time.Hour),
	}

	span.SetAttributes(
		attribute.String("user.location", userInfo.Location),
		attribute.String("user.timezone", userInfo.Timezone),
	)

	return userInfo, nil
}

// GetWeatherInfo simulates fetching weather information
func (c *Client) GetWeatherInfo(ctx context.Context, location string) (string, error) {
	tracer := otel.Tracer("external-api-client")
	ctx, span := tracer.Start(ctx, "GetWeatherInfo",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("external.service", "weather-api"),
			attribute.String("location", location),
		),
	)
	defer span.End()

	// Simulate external API call
	time.Sleep(30 * time.Millisecond)

	// Simulate weather data
	weather := []string{
		"Sunny ☀️", "Partly Cloudy ⛅", "Cloudy ☁️",
		"Rainy 🌧️", "Snowy ❄️", "Windy 💨",
	}

	// Use location hash for consistent weather
	hash := 0
	for _, c := range location {
		hash += int(c)
	}

	weatherCondition := weather[hash%len(weather)]

	span.SetAttributes(
		attribute.String("weather.condition", weatherCondition),
	)

	return weatherCondition, nil
}

// BatchLookup simulates a batch API call to fetch multiple pieces of data
func (c *Client) BatchLookup(ctx context.Context, names []string) (map[string]*UserInfo, error) {
	tracer := otel.Tracer("external-api-client")
	ctx, span := tracer.Start(ctx, "BatchLookup",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("external.service", "batch-api"),
			attribute.Int("batch.size", len(names)),
		),
	)
	defer span.End()

	// Simulate batch API call - slightly more efficient than individual calls
	time.Sleep(time.Duration(20*len(names)) * time.Millisecond)

	results := make(map[string]*UserInfo)
	for _, name := range names {
		userInfo, err := c.EnrichUserInfo(ctx, name)
		if err != nil {
			span.RecordError(err)
			continue
		}
		results[name] = userInfo
	}

	span.SetAttributes(
		attribute.Int("batch.results", len(results)),
	)

	return results, nil
}
