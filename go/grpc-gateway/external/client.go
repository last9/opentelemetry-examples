package external

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	httpagent "github.com/last9/go-agent/integrations/http"
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

// NewClient creates a new external API client with go-agent instrumentation
func NewClient(baseURL string) *Client {
	return &Client{
		httpClient: httpagent.NewClient(&http.Client{
			Timeout: 10 * time.Second,
		}),
		baseURL: baseURL,
	}
}

// GetInspirationalQuote fetches a random inspirational quote
// This simulates calling an external API service
// Automatically instrumented by go-agent HTTP client
func (c *Client) GetInspirationalQuote(ctx context.Context) (*Quote, error) {
	// Use a real public API for quotes
	req, err := http.NewRequestWithContext(ctx, "GET", "https://api.quotable.io/random", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch quote: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var quote Quote
	if err := json.Unmarshal(body, &quote); err != nil {
		return nil, fmt.Errorf("failed to parse quote: %w", err)
	}

	return &quote, nil
}

// EnrichUserInfo simulates fetching additional user information from an external service
// Note: This is a simulated method without actual HTTP calls
func (c *Client) EnrichUserInfo(ctx context.Context, name string) (*UserInfo, error) {
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

	return userInfo, nil
}

// GetWeatherInfo simulates fetching weather information
// Note: This is a simulated method without actual HTTP calls
func (c *Client) GetWeatherInfo(ctx context.Context, location string) (string, error) {
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

	return weatherCondition, nil
}

// BatchLookup simulates a batch API call to fetch multiple pieces of data
// Note: This is a simulated method without actual HTTP calls
func (c *Client) BatchLookup(ctx context.Context, names []string) (map[string]*UserInfo, error) {
	// Simulate batch API call - slightly more efficient than individual calls
	time.Sleep(time.Duration(20*len(names)) * time.Millisecond)

	results := make(map[string]*UserInfo)
	for _, name := range names {
		userInfo, err := c.EnrichUserInfo(ctx, name)
		if err != nil {
			continue
		}
		results[name] = userInfo
	}

	return results, nil
}
