package main

import (
	"context"
	"log/slog"
	"os"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi"
	taggingTypes "github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi/types"
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	metricsv1 "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	metricspb "go.opentelemetry.io/proto/otlp/metrics/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"

	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/enricher"
	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/otlp"
)

// mockTaggingClient implements enricher.TaggingClient for testing.
type mockTaggingClient struct {
	resources []taggingTypes.ResourceTagMapping
}

func (m *mockTaggingClient) GetResources(ctx context.Context, params *resourcegroupstaggingapi.GetResourcesInput, optFns ...func(*resourcegroupstaggingapi.Options)) (*resourcegroupstaggingapi.GetResourcesOutput, error) {
	return &resourcegroupstaggingapi.GetResourcesOutput{
		ResourceTagMappingList: m.resources,
	}, nil
}

// mockClientProvider implements enricher.ClientProvider for testing.
type mockClientProvider struct {
	taggingClient enricher.TaggingClient
}

func (m *mockClientProvider) GetClient(accountID string) enricher.TaggingClient {
	return m.taggingClient
}

func (m *mockClientProvider) CurrentAccountID() string {
	return "123456789012"
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func stringAttr(key, value string) *commonpb.KeyValue {
	return &commonpb.KeyValue{
		Key:   key,
		Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: value}},
	}
}

func buildTestFirehoseEvent() events.KinesisFirehoseEvent {
	req := &metricsv1.ExportMetricsServiceRequest{
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
								Name: "aws_ec2_cpu",
								Data: &metricspb.Metric_Summary{
									Summary: &metricspb.Summary{
										DataPoints: []*metricspb.SummaryDataPoint{
											{
												Attributes: []*commonpb.KeyValue{
													stringAttr("Namespace", "AWS/EC2"),
													stringAttr("MetricName", "CPUUtilization"),
													stringAttr("InstanceId", "i-1234567890abcdef0"),
												},
												Count: 1,
												Sum:   75.5,
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

	data, _ := otlp.EncodeRecords([]*metricsv1.ExportMetricsServiceRequest{req})

	return events.KinesisFirehoseEvent{
		Records: []events.KinesisFirehoseEventRecord{
			{
				RecordID: "record-1",
				Data:     data,
			},
		},
	}
}

func newMockProvider() *mockClientProvider {
	return &mockClientProvider{
		taggingClient: &mockTaggingClient{
			resources: []taggingTypes.ResourceTagMapping{
				{
					ResourceARN: aws.String("arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0"),
					Tags: []taggingTypes.Tag{
						{Key: aws.String("Name"), Value: aws.String("web-server")},
						{Key: aws.String("Environment"), Value: aws.String("production")},
					},
				},
			},
		},
	}
}

func TestHandler_ResponseContractPreserved(t *testing.T) {
	logger := testLogger()

	e := enricher.New(logger, newMockProvider(), enricher.NewTagCache(logger, t.TempDir(), 0), enricher.Config{
		ContinueOnError: true,
		Region:          "us-east-1",
	})

	handler := NewHandler(logger, e)
	event := buildTestFirehoseEvent()

	response, err := handler.HandleFirehoseEvent(context.Background(), event)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Firehose contract: same number of records, same order
	if len(response.Records) != len(event.Records) {
		t.Fatalf("expected %d response records, got %d", len(event.Records), len(response.Records))
	}

	for i, rec := range response.Records {
		if rec.RecordID != event.Records[i].RecordID {
			t.Errorf("record %d: RecordID mismatch: got %s, want %s", i, rec.RecordID, event.Records[i].RecordID)
		}
	}
}

func TestHandler_ResourceTagsInjected(t *testing.T) {
	logger := testLogger()

	e := enricher.New(logger, newMockProvider(), enricher.NewTagCache(logger, t.TempDir(), 0), enricher.Config{
		ContinueOnError: true,
		Region:          "us-east-1",
	})

	handler := NewHandler(logger, e)
	event := buildTestFirehoseEvent()

	response, err := handler.HandleFirehoseEvent(context.Background(), event)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	requests, err := otlp.DecodeRecords(response.Records[0].Data)
	if err != nil {
		t.Fatalf("failed to decode enriched data: %v", err)
	}

	dp := requests[0].ResourceMetrics[0].ScopeMetrics[0].Metrics[0].GetSummary().DataPoints[0]

	found := make(map[string]string)
	for _, attr := range dp.Attributes {
		found[attr.Key] = attr.GetValue().GetStringValue()
	}

	// AWS resource tags should be prefixed with aws_tag_
	if found["aws_tag_Name"] != "web-server" {
		t.Errorf("aws_tag_Name not found or wrong: %q", found["aws_tag_Name"])
	}
	if found["aws_tag_Environment"] != "production" {
		t.Errorf("aws_tag_Environment not found or wrong: %q", found["aws_tag_Environment"])
	}
}

func TestHandler_MultipleRecords(t *testing.T) {
	logger := testLogger()

	e := enricher.New(logger, newMockProvider(), enricher.NewTagCache(logger, t.TempDir(), 0), enricher.Config{
		ContinueOnError: true,
		Region:          "us-east-1",
	})

	handler := NewHandler(logger, e)

	data, _ := otlp.EncodeRecords([]*metricsv1.ExportMetricsServiceRequest{
		{ResourceMetrics: []*metricspb.ResourceMetrics{{}}},
	})

	event := events.KinesisFirehoseEvent{
		Records: []events.KinesisFirehoseEventRecord{
			{RecordID: "rec-1", Data: data},
			{RecordID: "rec-2", Data: data},
			{RecordID: "rec-3", Data: data},
		},
	}

	response, err := handler.HandleFirehoseEvent(context.Background(), event)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(response.Records) != 3 {
		t.Fatalf("expected 3 response records, got %d", len(response.Records))
	}

	for i, rec := range response.Records {
		if rec.RecordID != event.Records[i].RecordID {
			t.Errorf("record %d: RecordID mismatch", i)
		}
		if rec.Result != events.KinesisFirehoseTransformedStateOk {
			t.Errorf("record %d: expected Ok, got %s", i, rec.Result)
		}
	}
}

// buildOTel07FirehoseEvent creates a Firehose event that mimics the real
// CloudWatch Metric Streams OTel 0.7 wire format: metric identity is encoded
// in the metric Name field (e.g. "amazonaws.com/AWS/EC2/CPUUtilization")
// and datapoint attributes are empty.
func buildOTel07FirehoseEvent() events.KinesisFirehoseEvent {
	req := &metricsv1.ExportMetricsServiceRequest{
		ResourceMetrics: []*metricspb.ResourceMetrics{
			{
				Resource: &resourcepb.Resource{
					Attributes: []*commonpb.KeyValue{
						stringAttr("cloud.provider", "aws"),
						stringAttr("cloud.account.id", "123456789012"),
						stringAttr("cloud.region", "us-east-1"),
					},
				},
				ScopeMetrics: []*metricspb.ScopeMetrics{
					{
						Metrics: []*metricspb.Metric{
							{
								Name: "amazonaws.com/AWS/EC2/CPUUtilization",
								Data: &metricspb.Metric_Summary{
									Summary: &metricspb.Summary{
										DataPoints: []*metricspb.SummaryDataPoint{
											{
												Attributes: []*commonpb.KeyValue{},
												Count:      1,
												Sum:        75.5,
											},
										},
									},
								},
							},
							{
								Name: "amazonaws.com/AWS/RDS/DatabaseConnections",
								Data: &metricspb.Metric_Summary{
									Summary: &metricspb.Summary{
										DataPoints: []*metricspb.SummaryDataPoint{
											{
												Attributes: []*commonpb.KeyValue{},
												Count:      1,
												Sum:        42,
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

	data, _ := otlp.EncodeRecords([]*metricsv1.ExportMetricsServiceRequest{req})

	return events.KinesisFirehoseEvent{
		Records: []events.KinesisFirehoseEventRecord{
			{
				RecordID: "otel07-record-1",
				Data:     data,
			},
		},
	}
}

func TestHandler_InvalidDataReturnsProcessingFailed(t *testing.T) {
	logger := testLogger()

	e := enricher.New(logger, newMockProvider(), enricher.NewTagCache(logger, t.TempDir(), 0), enricher.Config{
		ContinueOnError: true,
		Region:          "us-east-1",
	})

	handler := NewHandler(logger, e)

	event := events.KinesisFirehoseEvent{
		Records: []events.KinesisFirehoseEventRecord{
			{
				RecordID: "bad-record",
				Data:     []byte("this is not valid protobuf"),
			},
		},
	}

	response, err := handler.HandleFirehoseEvent(context.Background(), event)
	if err != nil {
		t.Fatalf("handler should not return error (per-record failure): %v", err)
	}

	if len(response.Records) != 1 {
		t.Fatalf("expected 1 record, got %d", len(response.Records))
	}

	if response.Records[0].Result != events.KinesisFirehoseTransformedStateProcessingFailed {
		t.Errorf("expected ProcessingFailed, got %s", response.Records[0].Result)
	}
	if response.Records[0].RecordID != "bad-record" {
		t.Errorf("RecordID mismatch: %s", response.Records[0].RecordID)
	}
}
