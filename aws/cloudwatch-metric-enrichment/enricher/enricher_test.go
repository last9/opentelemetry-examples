package enricher

import "testing"

func TestParseMetricName(t *testing.T) {
	tests := []struct {
		name          string
		input         string
		wantNamespace string
		wantMetric    string
	}{
		{
			name:          "EC2 metric",
			input:         "amazonaws.com/AWS/EC2/CPUUtilization",
			wantNamespace: "AWS/EC2",
			wantMetric:    "CPUUtilization",
		},
		{
			name:          "RDS metric",
			input:         "amazonaws.com/AWS/RDS/DatabaseConnections",
			wantNamespace: "AWS/RDS",
			wantMetric:    "DatabaseConnections",
		},
		{
			name:          "metric with percent sign",
			input:         "amazonaws.com/AWS/RDS/EBSByteBalance%",
			wantNamespace: "AWS/RDS",
			wantMetric:    "EBSByteBalance%",
		},
		{
			name:          "DynamoDB metric",
			input:         "amazonaws.com/AWS/DynamoDB/ConsumedReadCapacityUnits",
			wantNamespace: "AWS/DynamoDB",
			wantMetric:    "ConsumedReadCapacityUnits",
		},
		{
			name:          "non-AWS metric name",
			input:         "some_other_metric",
			wantNamespace: "",
			wantMetric:    "",
		},
		{
			name:          "empty string",
			input:         "",
			wantNamespace: "",
			wantMetric:    "",
		},
		{
			name:          "prefix only",
			input:         "amazonaws.com/",
			wantNamespace: "",
			wantMetric:    "",
		},
		{
			name:          "prefix with namespace but no metric",
			input:         "amazonaws.com/AWS/EC2",
			wantNamespace: "",
			wantMetric:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ns, mn := parseMetricName(tt.input)
			if ns != tt.wantNamespace {
				t.Errorf("namespace: got %q, want %q", ns, tt.wantNamespace)
			}
			if mn != tt.wantMetric {
				t.Errorf("metricName: got %q, want %q", mn, tt.wantMetric)
			}
		})
	}
}
