package otlp

import (
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"
)

// CloudWatchMetric represents a CloudWatch metric extracted from OTLP attributes.
// CloudWatch Metric Streams encode the metric identity (Namespace, MetricName)
// and dimensions as OTLP datapoint attributes.
type CloudWatchMetric struct {
	Namespace  string
	MetricName string
	Dimensions map[string]string
}

// ExtractCloudWatchMetric builds a CloudWatchMetric from OTLP datapoint attributes.
// Attributes with keys "Namespace" and "MetricName" are treated as metric identity.
//
// In OTel 1.0 from CloudWatch Metric Streams, dimensions are packed in a single
// "Dimensions" attribute of type KvlistValue. In OTel 0.7 (or other formats),
// dimensions may appear as individual string attributes.
func ExtractCloudWatchMetric(attrs []*commonpb.KeyValue) CloudWatchMetric {
	cwm := CloudWatchMetric{
		Dimensions: make(map[string]string),
	}

	for _, attr := range attrs {
		switch attr.Key {
		case "MetricName":
			cwm.MetricName = attr.GetValue().GetStringValue()
		case "Namespace":
			cwm.Namespace = attr.GetValue().GetStringValue()
		case "Dimensions":
			// OTel 1.0: dimensions are a KvlistValue (nested key-value map)
			if kvlist := attr.GetValue().GetKvlistValue(); kvlist != nil {
				for _, kv := range kvlist.GetValues() {
					if v := kv.GetValue().GetStringValue(); v != "" {
						cwm.Dimensions[kv.Key] = v
					}
				}
			}
		default:
			// OTel 0.7 fallback: dimensions as individual string attributes
			if val := attr.GetValue().GetStringValue(); val != "" {
				cwm.Dimensions[attr.Key] = val
			}
		}
	}

	return cwm
}

// ExtractAccountID reads the "cloud.account.id" attribute from an OTLP Resource.
// CloudWatch Metric Streams include this attribute to identify the source AWS account,
// which is essential for cross-account tag enrichment.
func ExtractAccountID(resource *resourcepb.Resource) string {
	if resource == nil {
		return ""
	}
	for _, attr := range resource.Attributes {
		if attr.Key == "cloud.account.id" {
			return attr.GetValue().GetStringValue()
		}
	}
	return ""
}

// InjectAttributes appends key-value pairs as KeyValue entries to an existing
// attribute slice. Used for injecting resource tags.
func InjectAttributes(existing []*commonpb.KeyValue, labels map[string]string) []*commonpb.KeyValue {
	for k, v := range labels {
		existing = append(existing, &commonpb.KeyValue{
			Key: k,
			Value: &commonpb.AnyValue{
				Value: &commonpb.AnyValue_StringValue{StringValue: v},
			},
		})
	}
	return existing
}
