package otlp

import (
	"testing"

	metricsv1 "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	metricspb "go.opentelemetry.io/proto/otlp/metrics/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"
)

func stringAttr(key, value string) *commonpb.KeyValue {
	return &commonpb.KeyValue{
		Key:   key,
		Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: value}},
	}
}

func TestDecodeEncodeRoundTrip(t *testing.T) {
	original := []*metricsv1.ExportMetricsServiceRequest{
		{
			ResourceMetrics: []*metricspb.ResourceMetrics{
				{
					Resource: &resourcepb.Resource{
						Attributes: []*commonpb.KeyValue{
							stringAttr("cloud.account.id", "123456789012"),
						},
					},
					ScopeMetrics: []*metricspb.ScopeMetrics{
						{
							Metrics: []*metricspb.Metric{
								{
									Name: "test_metric",
									Data: &metricspb.Metric_Summary{
										Summary: &metricspb.Summary{
											DataPoints: []*metricspb.SummaryDataPoint{
												{
													Attributes: []*commonpb.KeyValue{
														stringAttr("Namespace", "AWS/EC2"),
														stringAttr("MetricName", "CPUUtilization"),
														stringAttr("InstanceId", "i-1234567890abcdef0"),
													},
													Count: 5,
													Sum:   42.5,
												},
											},
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}

	encoded, err := EncodeRecords(original)
	if err != nil {
		t.Fatalf("EncodeRecords failed: %v", err)
	}

	if len(encoded) == 0 {
		t.Fatal("EncodeRecords returned empty bytes")
	}

	decoded, err := DecodeRecords(encoded)
	if err != nil {
		t.Fatalf("DecodeRecords failed: %v", err)
	}

	if len(decoded) != 1 {
		t.Fatalf("expected 1 request, got %d", len(decoded))
	}

	rm := decoded[0].ResourceMetrics
	if len(rm) != 1 {
		t.Fatalf("expected 1 ResourceMetrics, got %d", len(rm))
	}

	sm := rm[0].ScopeMetrics
	if len(sm) != 1 {
		t.Fatalf("expected 1 ScopeMetrics, got %d", len(sm))
	}

	metrics := sm[0].Metrics
	if len(metrics) != 1 {
		t.Fatalf("expected 1 Metric, got %d", len(metrics))
	}

	summary := metrics[0].GetSummary()
	if summary == nil {
		t.Fatal("expected Summary metric type")
	}

	dp := summary.DataPoints[0]
	if dp.Count != 5 || dp.Sum != 42.5 {
		t.Errorf("datapoint values mismatch: count=%d sum=%f", dp.Count, dp.Sum)
	}
}

func TestDecodeEmptyInput(t *testing.T) {
	result, err := DecodeRecords([]byte{})
	if err != nil {
		t.Fatalf("unexpected error for empty input: %v", err)
	}
	if len(result) != 0 {
		t.Fatalf("expected 0 requests, got %d", len(result))
	}
}

func TestDecodeMultipleRequests(t *testing.T) {
	reqs := []*metricsv1.ExportMetricsServiceRequest{
		{ResourceMetrics: []*metricspb.ResourceMetrics{{}}},
		{ResourceMetrics: []*metricspb.ResourceMetrics{{}}},
		{ResourceMetrics: []*metricspb.ResourceMetrics{{}}},
	}

	encoded, err := EncodeRecords(reqs)
	if err != nil {
		t.Fatalf("EncodeRecords failed: %v", err)
	}

	decoded, err := DecodeRecords(encoded)
	if err != nil {
		t.Fatalf("DecodeRecords failed: %v", err)
	}

	if len(decoded) != 3 {
		t.Fatalf("expected 3 requests, got %d", len(decoded))
	}
}

func TestExtractCloudWatchMetric(t *testing.T) {
	attrs := []*commonpb.KeyValue{
		stringAttr("Namespace", "AWS/RDS"),
		stringAttr("MetricName", "DatabaseConnections"),
		stringAttr("DBInstanceIdentifier", "mydb"),
		stringAttr("EngineName", "postgres"),
	}

	cwm := ExtractCloudWatchMetric(attrs)

	if cwm.Namespace != "AWS/RDS" {
		t.Errorf("expected namespace AWS/RDS, got %s", cwm.Namespace)
	}
	if cwm.MetricName != "DatabaseConnections" {
		t.Errorf("expected metric name DatabaseConnections, got %s", cwm.MetricName)
	}
	if len(cwm.Dimensions) != 2 {
		t.Fatalf("expected 2 dimensions, got %d", len(cwm.Dimensions))
	}
	if cwm.Dimensions["DBInstanceIdentifier"] != "mydb" {
		t.Errorf("unexpected dimension value: %s", cwm.Dimensions["DBInstanceIdentifier"])
	}
}

func TestExtractCloudWatchMetric_EmptyAttrs(t *testing.T) {
	cwm := ExtractCloudWatchMetric(nil)
	if cwm.Namespace != "" || cwm.MetricName != "" {
		t.Error("expected empty metric from nil attrs")
	}
	if len(cwm.Dimensions) != 0 {
		t.Error("expected empty dimensions from nil attrs")
	}
}

func TestExtractAccountID(t *testing.T) {
	tests := []struct {
		name     string
		resource *resourcepb.Resource
		want     string
	}{
		{
			name:     "nil resource",
			resource: nil,
			want:     "",
		},
		{
			name:     "no attributes",
			resource: &resourcepb.Resource{},
			want:     "",
		},
		{
			name: "account ID present",
			resource: &resourcepb.Resource{
				Attributes: []*commonpb.KeyValue{
					stringAttr("cloud.provider", "aws"),
					stringAttr("cloud.account.id", "987654321098"),
				},
			},
			want: "987654321098",
		},
		{
			name: "no account ID attribute",
			resource: &resourcepb.Resource{
				Attributes: []*commonpb.KeyValue{
					stringAttr("cloud.provider", "aws"),
				},
			},
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractAccountID(tt.resource)
			if got != tt.want {
				t.Errorf("ExtractAccountID() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestInjectAttributes(t *testing.T) {
	existing := []*commonpb.KeyValue{
		stringAttr("original", "value"),
	}

	labels := map[string]string{
		"aws_tag_Environment": "production",
		"aws_tag_Team":        "platform",
	}

	result := InjectAttributes(existing, labels)

	if len(result) != 3 {
		t.Fatalf("expected 3 attributes, got %d", len(result))
	}

	if result[0].Key != "original" {
		t.Error("original attribute not preserved")
	}

	found := make(map[string]string)
	for _, attr := range result[1:] {
		found[attr.Key] = attr.GetValue().GetStringValue()
	}
	if found["aws_tag_Environment"] != "production" {
		t.Error("Environment tag not injected")
	}
	if found["aws_tag_Team"] != "platform" {
		t.Error("Team tag not injected")
	}
}

func TestInjectAttributes_EmptyMap(t *testing.T) {
	existing := []*commonpb.KeyValue{
		stringAttr("keep", "me"),
	}

	result := InjectAttributes(existing, map[string]string{})
	if len(result) != 1 {
		t.Fatalf("expected 1 attribute, got %d", len(result))
	}
}
