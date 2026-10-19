package otlp

import (
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	metricsv1 "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	metricspb "go.opentelemetry.io/proto/otlp/metrics/v1"
	"google.golang.org/protobuf/encoding/protowire"
)

// InjectOTel07Labels extracts StringKeyValue labels from raw OTLP 0.7 bytes
// and injects them as KeyValue attributes into the decoded request.
//
// CloudWatch Metric Streams with OpenTelemetry 0.7 output format encode
// dimensions as repeated StringKeyValue at field 7 of SummaryDataPoint:
//
//	message StringKeyValue { string key = 1; string value = 2; }
//
// The current OTLP proto library expects KeyValue at the same field number:
//
//	message KeyValue { string key = 1; AnyValue value = 2; }
//
// Since AnyValue is a message (not a string), the library silently drops
// the labels during standard deserialization. This function re-parses the
// raw bytes to recover them.
func InjectOTel07Labels(raw []byte, req *metricsv1.ExportMetricsServiceRequest) {
	rmIdx := 0
	forEachField(raw, func(num protowire.Number, data []byte) {
		if num != 1 { // ExportMetricsServiceRequest.resource_metrics
			return
		}
		if rmIdx >= len(req.ResourceMetrics) {
			rmIdx++
			return
		}
		rm := req.ResourceMetrics[rmIdx]
		rmIdx++

		smIdx := 0
		forEachField(data, func(num protowire.Number, data []byte) {
			if num != 2 { // ResourceMetrics.scope_metrics (same field for InstrumentationLibraryMetrics)
				return
			}
			if smIdx >= len(rm.ScopeMetrics) {
				smIdx++
				return
			}
			sm := rm.ScopeMetrics[smIdx]
			smIdx++

			mIdx := 0
			forEachField(data, func(num protowire.Number, data []byte) {
				if num != 2 { // ScopeMetrics.metrics
					return
				}
				if mIdx >= len(sm.Metrics) {
					mIdx++
					return
				}
				metric := sm.Metrics[mIdx]
				mIdx++

				injectMetricLabels(data, metric)
			})
		})
	})
}

// injectMetricLabels finds the data field (Summary, Gauge, Sum) in raw metric
// bytes and extracts labels from each datapoint.
func injectMetricLabels(metricBytes []byte, metric *metricspb.Metric) {
	forEachField(metricBytes, func(num protowire.Number, data []byte) {
		switch num {
		case 11: // Metric.summary
			if s := metric.GetSummary(); s != nil {
				injectSummaryLabels(data, s.DataPoints)
			}
		case 5: // Metric.gauge
			if g := metric.GetGauge(); g != nil {
				injectNumberLabels(data, g.DataPoints)
			}
		case 7: // Metric.sum
			if s := metric.GetSum(); s != nil {
				injectNumberLabels(data, s.DataPoints)
			}
		}
	})
}

func injectSummaryLabels(dataBytes []byte, dps []*metricspb.SummaryDataPoint) {
	dpIdx := 0
	forEachField(dataBytes, func(num protowire.Number, data []byte) {
		if num != 1 { // Summary.data_points
			return
		}
		if dpIdx >= len(dps) {
			dpIdx++
			return
		}
		dp := dps[dpIdx]
		dpIdx++

		if len(dp.Attributes) > 0 {
			return // already has attributes (OTel 1.0 format), skip
		}

		labels := extractStringKeyValues(data)
		if len(labels) > 0 {
			dp.Attributes = labels
		}
	})
}

func injectNumberLabels(dataBytes []byte, dps []*metricspb.NumberDataPoint) {
	dpIdx := 0
	forEachField(dataBytes, func(num protowire.Number, data []byte) {
		if num != 1 { // Gauge.data_points / Sum.data_points
			return
		}
		if dpIdx >= len(dps) {
			dpIdx++
			return
		}
		dp := dps[dpIdx]
		dpIdx++

		if len(dp.Attributes) > 0 {
			return
		}

		labels := extractStringKeyValues(data)
		if len(labels) > 0 {
			dp.Attributes = labels
		}
	})
}

// extractStringKeyValues parses field 7 entries from a datapoint as
// StringKeyValue (OTel 0.7 format) and converts to KeyValue.
func extractStringKeyValues(dpBytes []byte) []*commonpb.KeyValue {
	var labels []*commonpb.KeyValue
	forEachField(dpBytes, func(num protowire.Number, data []byte) {
		if num != 7 { // labels field (same number as attributes)
			return
		}
		key, value := parseStringKeyValue(data)
		if key != "" {
			labels = append(labels, &commonpb.KeyValue{
				Key: key,
				Value: &commonpb.AnyValue{
					Value: &commonpb.AnyValue_StringValue{StringValue: value},
				},
			})
		}
	})
	return labels
}

// parseStringKeyValue reads a StringKeyValue message: field 1 = key, field 2 = value.
func parseStringKeyValue(data []byte) (key, value string) {
	forEachField(data, func(num protowire.Number, fieldData []byte) {
		switch num {
		case 1:
			key = string(fieldData)
		case 2:
			value = string(fieldData)
		}
	})
	return
}

// forEachField iterates protobuf fields in serialized message bytes,
// calling fn for each length-delimited field (messages, strings, bytes).
// Non-length-delimited fields (varints, fixed32/64) are skipped.
func forEachField(data []byte, fn func(num protowire.Number, data []byte)) {
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return
		}
		data = data[n:]

		switch wtype {
		case protowire.BytesType:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return
			}
			data = data[n:]
			fn(num, val)

		case protowire.VarintType:
			_, n := protowire.ConsumeVarint(data)
			if n < 0 {
				return
			}
			data = data[n:]

		case protowire.Fixed32Type:
			_, n := protowire.ConsumeFixed32(data)
			if n < 0 {
				return
			}
			data = data[n:]

		case protowire.Fixed64Type:
			_, n := protowire.ConsumeFixed64(data)
			if n < 0 {
				return
			}
			data = data[n:]

		default:
			return
		}
	}
}
