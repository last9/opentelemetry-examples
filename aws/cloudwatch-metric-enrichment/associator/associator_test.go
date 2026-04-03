package associator

import (
	"log/slog"
	"os"
	"testing"

	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/model"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func TestAssociate_EC2Instance(t *testing.T) {
	resources := []*model.TaggedResource{
		{
			ARN:       "arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0",
			Namespace: "AWS/EC2",
			Region:    "us-east-1",
			Tags: []model.Tag{
				{Key: "Name", Value: "web-server"},
				{Key: "Environment", Value: "production"},
			},
		},
	}

	dimensions := map[string]string{
		"InstanceId": "i-1234567890abcdef0",
	}

	resource, skip := Associate(testLogger(), "AWS/EC2", dimensions, resources)
	if skip {
		t.Fatal("expected association, got skip")
	}
	if resource == nil {
		t.Fatal("expected resource match, got nil")
	}
	if resource.ARN != "arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0" {
		t.Errorf("unexpected ARN: %s", resource.ARN)
	}
	if len(resource.Tags) != 2 {
		t.Errorf("expected 2 tags, got %d", len(resource.Tags))
	}
}

func TestAssociate_UnsupportedNamespace(t *testing.T) {
	resource, skip := Associate(testLogger(), "Custom/MyApp", map[string]string{"key": "val"}, nil)
	if !skip {
		t.Error("expected skip for unsupported namespace")
	}
	if resource != nil {
		t.Error("expected nil resource for unsupported namespace")
	}
}

func TestAssociate_NoMatchingResource(t *testing.T) {
	resources := []*model.TaggedResource{
		{
			ARN:       "arn:aws:ec2:us-east-1:123456789012:instance/i-different",
			Namespace: "AWS/EC2",
			Region:    "us-east-1",
			Tags:      []model.Tag{{Key: "Name", Value: "other"}},
		},
	}

	dimensions := map[string]string{
		"InstanceId": "i-nonexistent",
	}

	resource, _ := Associate(testLogger(), "AWS/EC2", dimensions, resources)
	if resource != nil {
		t.Error("expected nil resource for non-matching dimensions")
	}
}

func TestAssociate_EmptyDimensions(t *testing.T) {
	resource, _ := Associate(testLogger(), "AWS/EC2", map[string]string{}, nil)
	// Empty dimensions should not match anything but shouldn't panic
	if resource != nil {
		t.Error("expected nil resource for empty dimensions")
	}
}
