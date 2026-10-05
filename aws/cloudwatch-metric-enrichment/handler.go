package main

import (
	"context"
	"log/slog"

	"github.com/aws/aws-lambda-go/events"

	"github.com/last9/opentelemetry-examples/aws/cloudwatch-metric-enrichment/enricher"
)

// Handler processes Kinesis Firehose transformation events. It enriches each
// record's OTLP metrics with AWS resource tags, maintaining
// the Firehose contract: exactly one output record per input record, same order,
// same RecordId.
type Handler struct {
	logger   *slog.Logger
	enricher *enricher.Enricher
}

// NewHandler creates a Handler with the given enricher.
func NewHandler(logger *slog.Logger, e *enricher.Enricher) *Handler {
	return &Handler{
		logger:   logger,
		enricher: e,
	}
}

// HandleFirehoseEvent processes a batch of Firehose records.
func (h *Handler) HandleFirehoseEvent(ctx context.Context, event events.KinesisFirehoseEvent) (events.KinesisFirehoseResponse, error) {
	h.logger.Info("processing firehose event", "records", len(event.Records))

	// Reset per-invocation cache for fresh resource lookups
	h.enricher.ResetInvocationCache()

	response := events.KinesisFirehoseResponse{
		Records: make([]events.KinesisFirehoseResponseRecord, 0, len(event.Records)),
	}

	for _, record := range event.Records {
		enrichedData, err := h.enricher.EnrichRecord(ctx, record.Data)
		if err != nil {
			h.logger.Error("failed to enrich record",
				"recordID", record.RecordID,
				"error", err,
			)
			// Return original data with ProcessingFailed — Firehose will
			// retry or route to the error S3 bucket.
			response.Records = append(response.Records, events.KinesisFirehoseResponseRecord{
				RecordID: record.RecordID,
				Result:   events.KinesisFirehoseTransformedStateProcessingFailed,
				Data:     record.Data,
			})
			continue
		}

		// Guard against enriched record exceeding Firehose's 1MB limit
		if len(enrichedData) > 1_000_000 {
			h.logger.Warn("enriched record exceeds 1MB, using original",
				"recordID", record.RecordID,
				"enrichedSize", len(enrichedData),
			)
			enrichedData = record.Data
		}

		response.Records = append(response.Records, events.KinesisFirehoseResponseRecord{
			RecordID: record.RecordID,
			Result:   events.KinesisFirehoseTransformedStateOk,
			Data:     enrichedData,
		})
	}

	h.logger.Info("firehose event processed", "records", len(response.Records))
	return response, nil
}
