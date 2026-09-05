package otlp

import (
	"math"
	"testing"

	"google.golang.org/protobuf/encoding/protowire"
	"google.golang.org/protobuf/proto"

	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	metricsv1 "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	metricspb "go.opentelemetry.io/proto/otlp/metrics/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"
)

// buildOTel07Raw constructs raw OTLP 0.7 bytes with StringKeyValue labels
// at field 7 of SummaryDataPoint. This simulates what CloudWatch Metric
// Streams actually produces.
func buildOTel07Raw(metricName string, labels map[string]string) []byte {
	// Build from innermost to outermost

	// SummaryDataPoint: labels (field 7 as StringKeyValue) + count + sum
	var dpBytes []byte
	for k, v := range labels {
		var label []byte
		label = protowire.AppendTag(label, 1, protowire.BytesType)
		label = protowire.AppendString(label, k)
		label = protowire.AppendTag(label, 2, protowire.BytesType)
		label = protowire.AppendString(label, v)

		dpBytes = protowire.AppendTag(dpBytes, 7, protowire.BytesType)
		dpBytes = protowire.AppendBytes(dpBytes, label)
	}
	// count (field 4, varint)
	dpBytes = protowire.AppendTag(dpBytes, 4, protowire.VarintType)
	dpBytes = protowire.AppendVarint(dpBytes, 1)
	// sum (field 5, fixed64/double)
	dpBytes = protowire.AppendTag(dpBytes, 5, protowire.Fixed64Type)
	dpBytes = protowire.AppendFixed64(dpBytes, math.Float64bits(42.5))

	// Summary: data_points (field 1)
	var summaryBytes []byte
	summaryBytes = protowire.AppendTag(summaryBytes, 1, protowire.BytesType)
	summaryBytes = protowire.AppendBytes(summaryBytes, dpBytes)

	// Metric: name (field 1) + summary (field 11)
	var metricBytes []byte
	metricBytes = protowire.AppendTag(metricBytes, 1, protowire.BytesType)
	metricBytes = protowire.AppendString(metricBytes, metricName)
	metricBytes = protowire.AppendTag(metricBytes, 11, protowire.BytesType)
	metricBytes = protowire.AppendBytes(metricBytes, summaryBytes)

	// ScopeMetrics: metrics (field 2)
	var smBytes []byte
	smBytes = protowire.AppendTag(smBytes, 2, protowire.BytesType)
	smBytes = protowire.AppendBytes(smBytes, metricBytes)

	// Resource: attributes (field 1) with cloud.account.id
	var accountAttr []byte
	accountAttr = protowire.AppendTag(accountAttr, 1, protowire.BytesType)
	accountAttr = protowire.AppendString(accountAttr, "cloud.account.id")
	// AnyValue with string_value (field 1)
	var accountValue []byte
	accountValue = protowire.AppendTag(accountValue, 1, protowire.BytesType)
	accountValue = protowire.AppendString(accountValue, "123456789012")
	accountAttr = protowire.AppendTag(accountAttr, 2, protowire.BytesType)
	accountAttr = protowire.AppendBytes(accountAttr, accountValue)

	var resourceBytes []byte
	resourceBytes = protowire.AppendTag(resourceBytes, 1, protowire.BytesType)
	resourceBytes = protowire.AppendBytes(resourceBytes, accountAttr)

	// ResourceMetrics: resource (field 1) + scope_metrics (field 2)
	var rmBytes []byte
	rmBytes = protowire.AppendTag(rmBytes, 1, protowire.BytesType)
	rmBytes = protowire.AppendBytes(rmBytes, resourceBytes)
	rmBytes = protowire.AppendTag(rmBytes, 2, protowire.BytesType)
	rmBytes = protowire.AppendBytes(rmBytes, smBytes)

	// ExportMetricsServiceRequest: resource_metrics (field 1)
	var reqBytes []byte
	reqBytes = protowire.AppendTag(reqBytes, 1, protowire.BytesType)
	reqBytes = protowire.AppendBytes(reqBytes, rmBytes)

	return reqBytes
}

func TestInjectOTel07Labels(t *testing.T) {
	raw := buildOTel07Raw(
		"amazonaws.com/AWS/EC2/CPUUtilization",
		map[string]string{
			"Namespace":  "AWS/EC2",
			"MetricName": "CPUUtilization",
			"InstanceId": "i-1234567890abcdef0",
		},
	)

	// Standard proto.Unmarshal rejects OTel 0.7 StringKeyValue as invalid
	// wire format. Strip labels first, then unmarshal, then inject from raw.
	stripped := StripOTel07Labels(raw)
	req := &metricsv1.ExportMetricsServiceRequest{}
	if err := proto.Unmarshal(stripped, req); err != nil {
		t.Fatalf("unmarshal of stripped data failed: %v", err)
	}

	if len(req.ResourceMetrics) != 1 {
		t.Fatalf("expected 1 ResourceMetrics, got %d", len(req.ResourceMetrics))
	}

	dp := req.ResourceMetrics[0].ScopeMetrics[0].Metrics[0].GetSummary().DataPoints[0]

	// Before injection: attributes should be empty
	if len(dp.Attributes) != 0 {
		t.Logf("Note: lenient decode preserved %d attributes", len(dp.Attributes))
	}

	// Inject labels from raw bytes
	InjectOTel07Labels(raw, req)

	if len(dp.Attributes) == 0 {
		t.Fatal("after injection, attributes should be populated")
	}

	found := make(map[string]string)
	for _, attr := range dp.Attributes {
		found[attr.Key] = attr.GetValue().GetStringValue()
	}

	if found["Namespace"] != "AWS/EC2" {
		t.Errorf("Namespace: got %q, want %q", found["Namespace"], "AWS/EC2")
	}
	if found["MetricName"] != "CPUUtilization" {
		t.Errorf("MetricName: got %q, want %q", found["MetricName"], "CPUUtilization")
	}
	if found["InstanceId"] != "i-1234567890abcdef0" {
		t.Errorf("InstanceId: got %q, want %q", found["InstanceId"], "i-1234567890abcdef0")
	}
}

func TestInjectOTel07Labels_SkipsWhenAttributesExist(t *testing.T) {
	// Build a standard OTel 1.0 request with proper KeyValue attributes
	req := &metricsv1.ExportMetricsServiceRequest{
		ResourceMetrics: []*metricspb.ResourceMetrics{
			{
				Resource: &resourcepb.Resource{
					Attributes: []*commonpb.KeyValue{
						{Key: "cloud.account.id", Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: "123"}}},
					},
				},
				ScopeMetrics: []*metricspb.ScopeMetrics{
					{
						Metrics: []*metricspb.Metric{
							{
								Name: "test",
								Data: &metricspb.Metric_Summary{
									Summary: &metricspb.Summary{
										DataPoints: []*metricspb.SummaryDataPoint{
											{
												Attributes: []*commonpb.KeyValue{
													{Key: "existing", Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: "value"}}},
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

	raw, err := proto.Marshal(req)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}

	// Inject should be a no-op since attributes already exist
	InjectOTel07Labels(raw, req)

	dp := req.ResourceMetrics[0].ScopeMetrics[0].Metrics[0].GetSummary().DataPoints[0]
	if len(dp.Attributes) != 1 {
		t.Errorf("expected 1 attribute (unchanged), got %d", len(dp.Attributes))
	}
	if dp.Attributes[0].Key != "existing" {
		t.Errorf("existing attribute was modified")
	}
}

func TestInjectOTel07Labels_MultipleMetrics(t *testing.T) {
	// Build raw bytes with two metrics, each having different labels
	ec2Raw := buildOTel07Raw(
		"amazonaws.com/AWS/EC2/CPUUtilization",
		map[string]string{
			"Namespace":  "AWS/EC2",
			"MetricName": "CPUUtilization",
			"InstanceId": "i-abc123",
		},
	)
	rdsRaw := buildOTel07Raw(
		"amazonaws.com/AWS/RDS/DatabaseConnections",
		map[string]string{
			"Namespace":            "AWS/RDS",
			"MetricName":           "DatabaseConnections",
			"DBInstanceIdentifier": "mydb",
		},
	)

	// Combine: build a single request with two metrics by constructing
	// the protobuf manually. For simplicity, use separate decode+inject calls.
	for _, tc := range []struct {
		name    string
		raw     []byte
		wantNS  string
		wantDim string
		wantVal string
	}{
		{"EC2", ec2Raw, "AWS/EC2", "InstanceId", "i-abc123"},
		{"RDS", rdsRaw, "AWS/RDS", "DBInstanceIdentifier", "mydb"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stripped := StripOTel07Labels(tc.raw)
			req := &metricsv1.ExportMetricsServiceRequest{}
			if err := proto.Unmarshal(stripped, req); err != nil {
				t.Fatalf("unmarshal failed: %v", err)
			}

			InjectOTel07Labels(tc.raw, req)

			dp := req.ResourceMetrics[0].ScopeMetrics[0].Metrics[0].GetSummary().DataPoints[0]
			found := make(map[string]string)
			for _, attr := range dp.Attributes {
				found[attr.Key] = attr.GetValue().GetStringValue()
			}

			if found["Namespace"] != tc.wantNS {
				t.Errorf("Namespace: got %q, want %q", found["Namespace"], tc.wantNS)
			}
			if found[tc.wantDim] != tc.wantVal {
				t.Errorf("%s: got %q, want %q", tc.wantDim, found[tc.wantDim], tc.wantVal)
			}
		})
	}
}

func TestDecodeRecords_WithOTel07Labels(t *testing.T) {
	raw := buildOTel07Raw(
		"amazonaws.com/AWS/EC2/CPUUtilization",
		map[string]string{
			"Namespace":  "AWS/EC2",
			"MetricName": "CPUUtilization",
			"InstanceId": "i-test123",
		},
	)

	// Wrap in size-delimited format (varint size prefix + message bytes)
	var delimited []byte
	delimited = protowire.AppendVarint(delimited, uint64(len(raw)))
	delimited = append(delimited, raw...)

	requests, err := DecodeRecords(delimited)
	if err != nil {
		t.Fatalf("DecodeRecords failed: %v", err)
	}

	if len(requests) != 1 {
		t.Fatalf("expected 1 request, got %d", len(requests))
	}

	dp := requests[0].ResourceMetrics[0].ScopeMetrics[0].Metrics[0].GetSummary().DataPoints[0]

	found := make(map[string]string)
	for _, attr := range dp.Attributes {
		found[attr.Key] = attr.GetValue().GetStringValue()
	}

	if found["InstanceId"] != "i-test123" {
		t.Errorf("InstanceId: got %q, want %q", found["InstanceId"], "i-test123")
	}
	if found["Namespace"] != "AWS/EC2" {
		t.Errorf("Namespace: got %q, want %q", found["Namespace"], "AWS/EC2")
	}
}
