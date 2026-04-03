package enricher

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi"
	taggingTypes "github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi/types"
	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/model"
)

type mockTaggingClient struct {
	resources []taggingTypes.ResourceTagMapping
	err       error
	callCount int
}

func (m *mockTaggingClient) GetResources(ctx context.Context, params *resourcegroupstaggingapi.GetResourcesInput, optFns ...func(*resourcegroupstaggingapi.Options)) (*resourcegroupstaggingapi.GetResourcesOutput, error) {
	m.callCount++
	if m.err != nil {
		return nil, m.err
	}
	return &resourcegroupstaggingapi.GetResourcesOutput{
		ResourceTagMappingList: m.resources,
	}, nil
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func TestTagCache_GetResources_FetchesFromAWS(t *testing.T) {
	cacheDir := t.TempDir()

	client := &mockTaggingClient{
		resources: []taggingTypes.ResourceTagMapping{
			{
				ResourceARN: aws.String("arn:aws:ec2:us-east-1:123456789012:instance/i-abc"),
				Tags: []taggingTypes.Tag{
					{Key: aws.String("Name"), Value: aws.String("web-1")},
					{Key: aws.String("Env"), Value: aws.String("prod")},
				},
			},
		},
	}

	tc := NewTagCache(testLogger(), cacheDir, 1*time.Hour)
	resources, err := tc.GetResources(context.Background(), client, "AWS/EC2", "123456789012", "us-east-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(resources) != 1 {
		t.Fatalf("expected 1 resource, got %d", len(resources))
	}
	if resources[0].ARN != "arn:aws:ec2:us-east-1:123456789012:instance/i-abc" {
		t.Errorf("unexpected ARN: %s", resources[0].ARN)
	}
	if len(resources[0].Tags) != 2 {
		t.Errorf("expected 2 tags, got %d", len(resources[0].Tags))
	}
	if client.callCount != 1 {
		t.Errorf("expected 1 API call, got %d", client.callCount)
	}
}

func TestTagCache_GetResources_UsesCache(t *testing.T) {
	cacheDir := t.TempDir()

	client := &mockTaggingClient{
		resources: []taggingTypes.ResourceTagMapping{
			{
				ResourceARN: aws.String("arn:aws:ec2:us-east-1:123456789012:instance/i-abc"),
				Tags:        []taggingTypes.Tag{{Key: aws.String("Name"), Value: aws.String("web-1")}},
			},
		},
	}

	tc := NewTagCache(testLogger(), cacheDir, 1*time.Hour)

	// First call: fetches from AWS
	_, err := tc.GetResources(context.Background(), client, "AWS/EC2", "123456789012", "us-east-1")
	if err != nil {
		t.Fatalf("first call failed: %v", err)
	}

	// Second call: should use cache
	resources, err := tc.GetResources(context.Background(), client, "AWS/EC2", "123456789012", "us-east-1")
	if err != nil {
		t.Fatalf("second call failed: %v", err)
	}

	if client.callCount != 1 {
		t.Errorf("expected 1 API call (cached), got %d", client.callCount)
	}
	if len(resources) != 1 {
		t.Errorf("expected 1 cached resource, got %d", len(resources))
	}
}

func TestTagCache_GetResources_ExpiredCache(t *testing.T) {
	cacheDir := t.TempDir()

	client := &mockTaggingClient{
		resources: []taggingTypes.ResourceTagMapping{
			{
				ResourceARN: aws.String("arn:aws:ec2:us-east-1:123456789012:instance/i-abc"),
				Tags:        []taggingTypes.Tag{},
			},
		},
	}

	// Use a very short TTL
	tc := NewTagCache(testLogger(), cacheDir, 1*time.Millisecond)

	// First call
	_, err := tc.GetResources(context.Background(), client, "AWS/EC2", "123456789012", "us-east-1")
	if err != nil {
		t.Fatalf("first call failed: %v", err)
	}

	// Wait for cache to expire
	time.Sleep(5 * time.Millisecond)

	// Second call should re-fetch
	_, err = tc.GetResources(context.Background(), client, "AWS/EC2", "123456789012", "us-east-1")
	if err != nil {
		t.Fatalf("second call failed: %v", err)
	}

	if client.callCount != 2 {
		t.Errorf("expected 2 API calls (cache expired), got %d", client.callCount)
	}
}

func TestTagCache_SeparatesCacheByAccount(t *testing.T) {
	cacheDir := t.TempDir()

	client := &mockTaggingClient{
		resources: []taggingTypes.ResourceTagMapping{
			{
				ResourceARN: aws.String("arn:aws:ec2:us-east-1:111:instance/i-1"),
				Tags:        []taggingTypes.Tag{},
			},
		},
	}

	tc := NewTagCache(testLogger(), cacheDir, 1*time.Hour)

	// Fetch for account 111
	_, _ = tc.GetResources(context.Background(), client, "AWS/EC2", "111", "us-east-1")

	// Fetch for account 222 — should make a new API call
	_, _ = tc.GetResources(context.Background(), client, "AWS/EC2", "222", "us-east-1")

	if client.callCount != 2 {
		t.Errorf("expected 2 API calls for different accounts, got %d", client.callCount)
	}

	// Verify separate cache files exist
	files, _ := filepath.Glob(filepath.Join(cacheDir, "*.json"))
	if len(files) != 2 {
		t.Errorf("expected 2 cache files, got %d", len(files))
	}
}

func TestPrefixTags(t *testing.T) {
	tags := []model.Tag{
		{Key: "Name", Value: "web-server"},
		{Key: "Environment", Value: "production"},
		{Key: "Team", Value: "platform"},
	}

	result := PrefixTags(tags)

	if len(result) != 3 {
		t.Fatalf("expected 3 prefixed tags, got %d", len(result))
	}
	if result["aws_tag_Name"] != "web-server" {
		t.Errorf("unexpected Name tag: %s", result["aws_tag_Name"])
	}
	if result["aws_tag_Environment"] != "production" {
		t.Errorf("unexpected Environment tag: %s", result["aws_tag_Environment"])
	}
}

func TestPrefixTags_Empty(t *testing.T) {
	result := PrefixTags(nil)
	if len(result) != 0 {
		t.Errorf("expected empty map, got %d entries", len(result))
	}
}
