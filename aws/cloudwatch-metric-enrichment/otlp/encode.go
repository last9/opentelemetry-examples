package otlp

import (
	"bytes"

	"github.com/matttproud/golang_protobuf_extensions/v2/pbutil"
	metricsv1 "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
)

// EncodeRecords writes OTLP ExportMetricsServiceRequest messages back to
// size-delimited protobuf format, matching CloudWatch Metric Streams' wire format.
func EncodeRecords(requests []*metricsv1.ExportMetricsServiceRequest) ([]byte, error) {
	var buf bytes.Buffer

	for _, req := range requests {
		if _, err := pbutil.WriteDelimited(&buf, req); err != nil {
			return nil, err
		}
	}

	return buf.Bytes(), nil
}
