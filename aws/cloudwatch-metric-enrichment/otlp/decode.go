package otlp

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"

	metricsv1 "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	"google.golang.org/protobuf/proto"
)

// DecodeRecords reads size-delimited OTLP ExportMetricsServiceRequest messages
// from raw bytes. CloudWatch Metric Streams emit OTLP v0.7 in this format
// when delivered through Kinesis Data Firehose.
//
// It handles the OTel 0.7 StringKeyValue label format by:
// 1. Keeping a copy of the original raw bytes (which contain StringKeyValue labels)
// 2. Stripping field 7 from SummaryDataPoints so proto.Unmarshal succeeds
// 3. Extracting labels from the original raw bytes and injecting as KeyValue attributes
func DecodeRecords(data []byte) ([]*metricsv1.ExportMetricsServiceRequest, error) {
	var requests []*metricsv1.ExportMetricsServiceRequest
	r := bytes.NewBuffer(data)

	for {
		rawMsg, err := readDelimitedRaw(r)
		if err != nil {
			if err == io.EOF {
				break
			}
			return nil, fmt.Errorf("read delimited message: %w", err)
		}

		req := &metricsv1.ExportMetricsServiceRequest{}

		// Try standard unmarshal first (works for OTel 1.0 and production
		// data where labels may already be absent).
		if err := proto.Unmarshal(rawMsg, req); err != nil {
			// If standard unmarshal fails (OTel 0.7 StringKeyValue causes
			// invalid wire format), strip the labels from raw bytes and retry.
			req.Reset()
			stripped := StripOTel07Labels(rawMsg)
			if err := proto.Unmarshal(stripped, req); err != nil {
				return nil, fmt.Errorf("unmarshal OTLP request: %w", err)
			}
		}

		// Recover OTel 0.7 StringKeyValue labels from the original raw
		// bytes and inject as proper KeyValue attributes. No-op for OTel
		// 1.0 data where attributes are already populated.
		InjectOTel07Labels(rawMsg, req)

		requests = append(requests, req)
	}

	return requests, nil
}

// readDelimitedRaw reads a size-delimited protobuf message as raw bytes
// without unmarshaling. The size prefix is a varint followed by that many
// bytes of message data.
func readDelimitedRaw(r *bytes.Buffer) ([]byte, error) {
	size, err := binary.ReadUvarint(r)
	if err != nil {
		return nil, err
	}
	if size == 0 {
		return []byte{}, nil
	}
	buf := make([]byte, size)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}
	return buf, nil
}
