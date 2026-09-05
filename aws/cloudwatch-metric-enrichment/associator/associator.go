package associator

import (
	"log/slog"

	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/config"
	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/job/maxdimassociator"
	"github.com/prometheus-community/yet-another-cloudwatch-exporter/pkg/model"
)

// Associate maps a CloudWatch metric to its AWS resource. Returns the matched
// resource and its tags, or nil if no match is found. The skip flag indicates
// the metric was intentionally skipped (e.g., unsupported namespace).
func Associate(logger *slog.Logger, namespace string, dimensions map[string]string, resources []*model.TaggedResource) (*model.TaggedResource, bool) {
	svc := config.SupportedServices.GetService(namespace)
	if svc == nil {
		logger.Debug("unsupported CloudWatch namespace for association", "namespace", namespace)
		return nil, true
	}

	// Build the metric model expected by maxdimassociator
	metric := &model.Metric{
		Namespace:  namespace,
		MetricName: "", // Not needed for association
		Dimensions: make([]model.Dimension, 0, len(dimensions)),
	}
	for name, value := range dimensions {
		metric.Dimensions = append(metric.Dimensions, model.Dimension{
			Name:  name,
			Value: value,
		})
	}

	assoc := maxdimassociator.NewAssociator(
		logger,
		svc.ToModelDimensionsRegexp(),
		resources,
	)

	resource, skip := assoc.AssociateMetricToResource(metric)
	return resource, skip
}
