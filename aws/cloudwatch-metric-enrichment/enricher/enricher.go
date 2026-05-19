package enricher

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	metricspb "go.opentelemetry.io/proto/otlp/metrics/v1"

	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/associator"
	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/otlp"

	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/model"
)

// ClientProvider returns the correct Tagging API client for a given AWS account.
type ClientProvider interface {
	GetClient(accountID string) TaggingClient
	CurrentAccountID() string
}

// Enricher enriches CloudWatch Metric Stream records with AWS resource tags.
// It maintains per-namespace resource caches and reuses them across records
// within a single Lambda invocation.
type Enricher struct {
	logger        *slog.Logger
	clients       ClientProvider
	tagCache      *TagCache
	continueOnErr bool
	region        string

	// Per-invocation resource cache: "accountID:namespace" -> resources
	resourceCache map[string][]*model.TaggedResource
}

// Config holds enricher configuration parsed from environment variables.
type Config struct {
	ContinueOnError bool
	Region          string
}

// New creates an Enricher with the given configuration.
func New(logger *slog.Logger, clients ClientProvider, tagCache *TagCache, cfg Config) *Enricher {
	return &Enricher{
		logger:        logger,
		clients:       clients,
		tagCache:      tagCache,
		continueOnErr: cfg.ContinueOnError,
		region:        cfg.Region,
		resourceCache: make(map[string][]*model.TaggedResource),
	}
}

// EnrichRecord decodes an OTLP record, enriches metrics with resource tags,
// then re-encodes. Returns the enriched bytes.
func (e *Enricher) EnrichRecord(ctx context.Context, data []byte) ([]byte, error) {
	requests, err := otlp.DecodeRecords(data)
	if err != nil {
		return nil, fmt.Errorf("decode OTLP records: %w", err)
	}

	for _, req := range requests {
		for _, rm := range req.ResourceMetrics {
			accountID := otlp.ExtractAccountID(rm.Resource)

			for _, sm := range rm.ScopeMetrics {
				for _, metric := range sm.Metrics {
					e.enrichMetric(ctx, metric, accountID)
				}
			}
		}
	}

	enriched, err := otlp.EncodeRecords(requests)
	if err != nil {
		return nil, fmt.Errorf("encode enriched records: %w", err)
	}

	return enriched, nil
}

// parseMetricName extracts the CloudWatch Namespace and MetricName from the
// OTLP metric Name field. CloudWatch Metric Streams (OTel 0.7) encode the
// metric identity in the Name field as:
//
//	amazonaws.com/AWS/<Service>/<MetricName>
//
// For example: "amazonaws.com/AWS/RDS/CPUUtilization" -> ("AWS/RDS", "CPUUtilization")
func parseMetricName(name string) (namespace, metricName string) {
	const prefix = "amazonaws.com/"
	if !strings.HasPrefix(name, prefix) {
		return "", ""
	}
	rest := name[len(prefix):] // e.g. "AWS/RDS/CPUUtilization"

	// Valid format requires at least "AWS/<Service>/<MetricName>" (two slashes).
	// The namespace is "AWS/<Service>" and the metric name follows the last slash.
	lastSlash := strings.LastIndex(rest, "/")
	if lastSlash <= 0 {
		return "", ""
	}

	ns := rest[:lastSlash]
	mn := rest[lastSlash+1:]

	// Namespace must contain at least one "/" (e.g. "AWS/EC2"), and
	// metric name must be non-empty.
	if !strings.Contains(ns, "/") || mn == "" {
		return "", ""
	}

	return ns, mn
}

// enrichMetric handles all OTLP metric data types. CloudWatch Metric Streams
// primarily emit Summary metrics, but we handle Gauge, Sum, and Histogram
// for completeness.
//
// In OTel 0.7 format from CloudWatch Metric Streams, the metric identity
// (Namespace + MetricName) is encoded in the metric Name field rather than
// as datapoint attributes. Dimensions may also be absent from datapoint
// attributes. We parse the metric Name to extract the identity and use it
// for tag enrichment.
func (e *Enricher) enrichMetric(ctx context.Context, metric *metricspb.Metric, accountID string) {
	// First try to extract identity from the metric Name field (OTel 0.7 format).
	namespace, metricName := parseMetricName(metric.Name)

	switch data := metric.Data.(type) {
	case *metricspb.Metric_Summary:
		if data.Summary == nil {
			return
		}
		for _, dp := range data.Summary.DataPoints {
			e.enrichDatapoint(ctx, &dp.Attributes, dp.Attributes, accountID, namespace, metricName)
		}

	case *metricspb.Metric_Gauge:
		if data.Gauge == nil {
			return
		}
		for _, dp := range data.Gauge.DataPoints {
			e.enrichDatapoint(ctx, &dp.Attributes, dp.Attributes, accountID, namespace, metricName)
		}

	case *metricspb.Metric_Sum:
		if data.Sum == nil {
			return
		}
		for _, dp := range data.Sum.DataPoints {
			e.enrichDatapoint(ctx, &dp.Attributes, dp.Attributes, accountID, namespace, metricName)
		}

	case *metricspb.Metric_Histogram:
		if data.Histogram == nil {
			return
		}
		for _, dp := range data.Histogram.DataPoints {
			e.enrichDatapoint(ctx, &dp.Attributes, dp.Attributes, accountID, namespace, metricName)
		}
	}
}

// enrichDatapoint enriches a single datapoint by looking up resource tags
// and injecting them as attributes.
//
// The namespace and metricName parameters come from parsing the metric Name
// field (OTel 0.7). If datapoint attributes contain Namespace/MetricName
// (OTel 1.0 or future formats), those take precedence.
func (e *Enricher) enrichDatapoint(ctx context.Context, attrsPtr *[]*commonpb.KeyValue, attrs []*commonpb.KeyValue, accountID, namespace, metricName string) {
	cwm := otlp.ExtractCloudWatchMetric(attrs)

	// Fall back to metric Name-derived identity if datapoint attrs are empty
	// (OTel 0.7 format from CloudWatch Metric Streams).
	if cwm.Namespace == "" {
		cwm.Namespace = namespace
	}
	if cwm.MetricName == "" {
		cwm.MetricName = metricName
	}

	if cwm.MetricName == "" || cwm.Namespace == "" {
		return
	}

	// Attempt tag enrichment only if we have dimensions to match against.
	if len(cwm.Dimensions) > 0 {
		tags := e.getResourceTags(ctx, cwm, accountID)
		if tags != nil {
			*attrsPtr = otlp.InjectAttributes(*attrsPtr, tags)
		}
	}
}

func (e *Enricher) getResourceTags(ctx context.Context, cwm otlp.CloudWatchMetric, accountID string) map[string]string {
	cacheKey := accountID + ":" + cwm.Namespace

	if _, ok := e.resourceCache[cacheKey]; !ok {
		client := e.clients.GetClient(accountID)
		resources, err := e.tagCache.GetResources(ctx, client, cwm.Namespace, accountID, e.region)
		if err != nil {
			e.logger.Error("failed to get resources", "namespace", cwm.Namespace, "accountID", accountID, "error", err)
			e.resourceCache[cacheKey] = []*model.TaggedResource{}
			return nil
		}
		e.resourceCache[cacheKey] = resources
	}

	resources := e.resourceCache[cacheKey]
	if len(resources) == 0 {
		return nil
	}

	resource, skip := associator.Associate(e.logger, cwm.Namespace, cwm.Dimensions, resources)
	if resource == nil || skip {
		return nil
	}

	e.logger.Debug("enriching metric", "namespace", cwm.Namespace, "metric", cwm.MetricName, "tags", len(resource.Tags))
	return PrefixTags(resource.Tags)
}

// ResetInvocationCache clears the per-invocation resource cache.
// Called between Lambda invocations to prevent stale data.
func (e *Enricher) ResetInvocationCache() {
	e.resourceCache = make(map[string][]*model.TaggedResource)
}
