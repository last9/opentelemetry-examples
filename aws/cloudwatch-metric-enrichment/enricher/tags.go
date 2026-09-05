package enricher

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi"
	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/model"
)

// safeCacheKeyChars only allows alphanumeric characters, hyphens, and underscores.
var safeCacheKeyChars = regexp.MustCompile(`[^a-zA-Z0-9_-]`)

// TaggingClient abstracts the AWS Resource Groups Tagging API for testability.
type TaggingClient interface {
	GetResources(ctx context.Context, params *resourcegroupstaggingapi.GetResourcesInput, optFns ...func(*resourcegroupstaggingapi.Options)) (*resourcegroupstaggingapi.GetResourcesOutput, error)
}

// TagCache fetches and caches AWS resource tags per namespace. The file-based
// cache in /tmp survives across warm Lambda invocations within the same
// execution environment, reducing API calls.
type TagCache struct {
	logger     *slog.Logger
	cacheDir   string
	cacheTTL   time.Duration
	maxEntries int
}

// NewTagCache creates a TagCache with the specified TTL and cache directory.
func NewTagCache(logger *slog.Logger, cacheDir string, cacheTTL time.Duration) *TagCache {
	return &TagCache{
		logger:     logger,
		cacheDir:   cacheDir,
		cacheTTL:   cacheTTL,
		maxEntries: 10000,
	}
}

// GetResources retrieves tagged resources for a CloudWatch namespace, using the
// file cache when available. The cache key combines namespace and accountID to
// prevent cross-account cache collisions.
func (tc *TagCache) GetResources(ctx context.Context, client TaggingClient, namespace, accountID, region string) ([]*model.TaggedResource, error) {
	// Sanitize the cache key: strip all characters except alphanumeric, hyphens, underscores.
	// This prevents path traversal via malicious namespace/accountID values (e.g. "../../etc").
	sanitized := safeCacheKeyChars.ReplaceAllString(
		accountID+"-"+strings.ReplaceAll(namespace, "/", "-"), "_",
	)
	if strings.Contains(sanitized, "..") || strings.Contains(sanitized, "/") || strings.Contains(sanitized, "\\") {
		return nil, fmt.Errorf("invalid cache key for %s/%s", accountID, namespace)
	}

	absCache, err := filepath.Abs(tc.cacheDir)
	if err != nil {
		return nil, fmt.Errorf("resolve cache dir: %w", err)
	}
	filePath, err := filepath.Abs(filepath.Join(tc.cacheDir, sanitized+".json"))
	if err != nil {
		return nil, fmt.Errorf("resolve cache path: %w", err)
	}
	if !strings.HasPrefix(filePath, absCache+string(filepath.Separator)) {
		return nil, fmt.Errorf("cache path escapes directory for %s/%s", accountID, namespace)
	}

	// Try reading from cache
	if resources, ok := tc.readCache(filePath); ok {
		tc.logger.Debug("tag cache hit", "namespace", namespace, "accountID", accountID, "count", len(resources))
		return resources, nil
	}

	tc.logger.Info("tag cache miss, fetching from AWS", "namespace", namespace, "accountID", accountID)

	// Fetch from AWS
	resources, err := tc.fetchResources(ctx, client, namespace, region)
	if err != nil {
		return nil, fmt.Errorf("fetch resources for %s: %w", namespace, err)
	}

	// Write to cache
	tc.writeCache(filePath, resources)

	tc.logger.Info("cached resources", "namespace", namespace, "count", len(resources))
	return resources, nil
}

func (tc *TagCache) readCache(filePath string) ([]*model.TaggedResource, bool) {
	info, err := os.Stat(filePath)
	if err != nil {
		return nil, false
	}

	if time.Since(info.ModTime()) > tc.cacheTTL {
		tc.logger.Debug("tag cache expired", "path", filePath)
		return nil, false
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, false
	}

	var resources []*model.TaggedResource
	if err := json.Unmarshal(data, &resources); err != nil {
		tc.logger.Warn("corrupt cache file, ignoring", "path", filePath, "error", err)
		return nil, false
	}

	return resources, true
}

func (tc *TagCache) writeCache(filePath string, resources []*model.TaggedResource) {
	if err := os.MkdirAll(tc.cacheDir, 0o755); err != nil {
		tc.logger.Warn("failed to create cache dir", "error", err)
		return
	}

	data, err := json.Marshal(resources)
	if err != nil {
		tc.logger.Warn("failed to marshal resources for cache", "error", err)
		return
	}

	if err := os.WriteFile(filePath, data, 0o644); err != nil {
		tc.logger.Warn("failed to write cache file", "error", err)
	}
}

// fetchResources calls the AWS Resource Groups Tagging API to retrieve all
// resources in a given namespace, paginating through results.
func (tc *TagCache) fetchResources(ctx context.Context, client TaggingClient, namespace, region string) ([]*model.TaggedResource, error) {
	// Map CloudWatch namespace to resource type filter
	resourceFilter := namespaceToResourceTypeFilter(namespace)

	var resources []*model.TaggedResource
	var paginationToken *string

	for {
		input := &resourcegroupstaggingapi.GetResourcesInput{
			PaginationToken: paginationToken,
		}
		if resourceFilter != "" {
			input.ResourceTypeFilters = []string{resourceFilter}
		}

		output, err := client.GetResources(ctx, input)
		if err != nil {
			return nil, err
		}

		for _, mapping := range output.ResourceTagMappingList {
			if mapping.ResourceARN == nil {
				continue
			}

			tags := make([]model.Tag, 0, len(mapping.Tags))
			for _, t := range mapping.Tags {
				tags = append(tags, model.Tag{
					Key:   aws.ToString(t.Key),
					Value: aws.ToString(t.Value),
				})
			}

			resources = append(resources, &model.TaggedResource{
				ARN:       aws.ToString(mapping.ResourceARN),
				Namespace: namespace,
				Region:    region,
				Tags:      tags,
			})
		}

		paginationToken = output.PaginationToken
		if paginationToken == nil || *paginationToken == "" {
			break
		}
	}

	return resources, nil
}

// namespaceToResourceTypeFilter maps CloudWatch namespaces to AWS resource type
// filters for the Tagging API. This improves API efficiency by only fetching
// resources of the relevant type.
func namespaceToResourceTypeFilter(namespace string) string {
	filters := map[string]string{
		"AWS/EC2":            "ec2:instance",
		"AWS/RDS":            "rds:db",
		"AWS/ELB":            "elasticloadbalancing:loadbalancer",
		"AWS/ALB":            "elasticloadbalancing:loadbalancer",
		"AWS/NLB":            "elasticloadbalancing:loadbalancer",
		"AWS/Lambda":         "lambda:function",
		"AWS/S3":             "s3",
		"AWS/SQS":            "sqs",
		"AWS/SNS":            "sns",
		"AWS/DynamoDB":       "dynamodb:table",
		"AWS/ECS":            "ecs:cluster",
		"AWS/ElastiCache":    "elasticache:cluster",
		"AWS/ES":             "es:domain",
		"AWS/Kafka":          "kafka:cluster",
		"AWS/Kinesis":        "kinesis:stream",
		"AWS/ApiGateway":     "apigateway",
		"AWS/CloudFront":     "cloudfront:distribution",
		"AWS/DocDB":          "rds:db",
		"AWS/Neptune":        "rds:db",
		"AWS/Redshift":       "redshift:cluster",
		"AWS/AutoScaling":    "autoscaling:autoScalingGroup",
		"AWS/EBS":            "ec2:volume",
		"AWS/NATGateway":     "ec2:natgateway",
		"AWS/TransitGateway": "ec2:transit-gateway",
	}
	return filters[namespace]
}

// PrefixTags adds the "aws_tag_" prefix to all tag keys to avoid collisions
// with metric dimensions in the OTLP attribute namespace.
func PrefixTags(tags []model.Tag) map[string]string {
	result := make(map[string]string, len(tags))
	for _, t := range tags {
		result["aws_tag_"+t.Key] = t.Value
	}
	return result
}
