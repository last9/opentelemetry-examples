package otlp

import (
	"google.golang.org/protobuf/encoding/protowire"
)

// StripOTel07Labels removes field 7 (StringKeyValue labels) from all
// SummaryDataPoints in the raw OTLP bytes, producing bytes that can be
// safely parsed by proto.Unmarshal (which expects KeyValue at field 7).
//
// This is needed because the OTel 0.7 StringKeyValue format causes
// proto.Unmarshal to fail with "cannot parse invalid wire-format data".
func StripOTel07Labels(raw []byte) []byte {
	return rewriteMessage(raw, 0, func(depth int, num protowire.Number, _ []byte) bool {
		// Strip field 7 at depth 5 (SummaryDataPoint.labels)
		// Path: Request(0) > ResourceMetrics(1) > ScopeMetrics(2) > Metric(3) > Summary(4) > DataPoint(5)
		// At depth 5, field 7 is StringKeyValue labels in OTel 0.7
		return depth == 5 && num == 7
	})
}

// rewriteMessage copies protobuf bytes, recursively descending into
// length-delimited fields, and skipping any field where shouldStrip returns true.
func rewriteMessage(data []byte, depth int, shouldStrip func(depth int, num protowire.Number, data []byte) bool) []byte {
	var out []byte
	for len(data) > 0 {
		num, wtype, tagLen := protowire.ConsumeTag(data)
		if tagLen < 0 {
			return append(out, data...)
		}

		switch wtype {
		case protowire.BytesType:
			val, valLen := protowire.ConsumeBytes(data[tagLen:])
			if valLen < 0 {
				return append(out, data...)
			}
			totalLen := tagLen + valLen

			if shouldStrip(depth, num, val) {
				data = data[totalLen:]
				continue
			}

			// Recurse into nested messages to strip at deeper levels
			if isContainerField(depth, num) {
				rewritten := rewriteMessage(val, depth+1, shouldStrip)
				out = protowire.AppendTag(out, num, protowire.BytesType)
				out = protowire.AppendBytes(out, rewritten)
			} else {
				out = append(out, data[:totalLen]...)
			}
			data = data[totalLen:]

		case protowire.VarintType:
			_, n := protowire.ConsumeVarint(data[tagLen:])
			if n < 0 {
				return append(out, data...)
			}
			out = append(out, data[:tagLen+n]...)
			data = data[tagLen+n:]

		case protowire.Fixed32Type:
			_, n := protowire.ConsumeFixed32(data[tagLen:])
			if n < 0 {
				return append(out, data...)
			}
			out = append(out, data[:tagLen+n]...)
			data = data[tagLen+n:]

		case protowire.Fixed64Type:
			_, n := protowire.ConsumeFixed64(data[tagLen:])
			if n < 0 {
				return append(out, data...)
			}
			out = append(out, data[:tagLen+n]...)
			data = data[tagLen+n:]

		default:
			return append(out, data...)
		}
	}
	return out
}

// isContainerField returns true for protobuf fields that contain nested
// messages we need to recurse into for label stripping.
func isContainerField(depth int, num protowire.Number) bool {
	switch depth {
	case 0:
		return num == 1 // ExportMetricsServiceRequest.resource_metrics
	case 1:
		return num == 2 // ResourceMetrics.scope_metrics
	case 2:
		return num == 2 // ScopeMetrics.metrics
	case 3:
		return num == 5 || num == 7 || num == 11 // Metric.gauge / sum / summary
	case 4:
		return num == 1 // Summary.data_points / Gauge.data_points / Sum.data_points
	default:
		return false // depth 5 = DataPoint level; field 7 here is labels (to strip)
	}
}
