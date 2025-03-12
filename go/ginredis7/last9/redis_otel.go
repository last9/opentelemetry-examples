package last9

import (
	"context"
	"fmt"
	"strings"

	"github.com/go-redis/redis/v7"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// OtelHook is a Redis hook that adds OpenTelemetry instrumentation
type OtelHook struct {
	tracer trace.Tracer
}

// NewOtelHook creates a new Redis hook with OpenTelemetry instrumentation
func NewOtelHook(tracerName string) *OtelHook {
	return &OtelHook{
		tracer: otel.Tracer(tracerName),
	}
}

// BeforeProcess implements redis.Hook interface
func (h *OtelHook) BeforeProcess(ctx context.Context, cmd redis.Cmder) (context.Context, error) {
	if ctx == nil {
		ctx = context.Background()
	}

	cmdName := cmd.Name()
	spanName := fmt.Sprintf("redis:%s", cmdName)

	// Get the parent span context if it exists
	ctx, span := h.tracer.Start(ctx, spanName, trace.WithSpanKind(trace.SpanKindClient))

	// Add db.* semantic attributes consistently
	span.SetAttributes(
		attribute.String("db.system", "redis"),
		attribute.String("db.operation", cmdName),
		attribute.String("db.statement", formatCmd(cmd)),
	)

	// Store the span in the context to access it in AfterProcess
	ctx = context.WithValue(ctx, cmdName, span)
	return ctx, nil
}

// AfterProcess implements redis.Hook interface
func (h *OtelHook) AfterProcess(ctx context.Context, cmd redis.Cmder) error {
	if ctx == nil {
		return nil
	}

	if span, ok := ctx.Value(cmd.Name()).(trace.Span); ok {
		if err := cmd.Err(); err != nil && err != redis.Nil {
			// Record error in the span
			span.RecordError(err)
		}

		span.End()
	}

	return nil
}

// BeforeProcessPipeline implements redis.Hook interface
func (h *OtelHook) BeforeProcessPipeline(ctx context.Context, cmds []redis.Cmder) (context.Context, error) {
	if ctx == nil {
		ctx = context.Background()
	}

	ctx, span := h.tracer.Start(ctx, "redis:pipeline", trace.WithSpanKind(trace.SpanKindClient))

	// Create a combined statement for the pipeline
	var statements []string
	for _, cmd := range cmds {
		statements = append(statements, formatCmd(cmd))
	}
	pipelineStatement := strings.Join(statements, "; ")

	// Add db.* semantic attributes consistently
	span.SetAttributes(
		attribute.String("db.system", "redis"),
		attribute.String("db.operation", "pipeline"),
		attribute.String("db.statement", pipelineStatement),
		attribute.Int("redis.num_commands", len(cmds)),
	)

	// Store the span in the context
	ctx = context.WithValue(ctx, "pipeline", span)
	return ctx, nil
}

// AfterProcessPipeline implements redis.Hook interface
func (h *OtelHook) AfterProcessPipeline(ctx context.Context, cmds []redis.Cmder) error {
	if ctx == nil {
		return nil
	}

	if span, ok := ctx.Value("pipeline").(trace.Span); ok {
		// Check for errors
		for _, cmd := range cmds {
			if err := cmd.Err(); err != nil && err != redis.Nil {
				span.RecordError(err)
				break
			}
		}

		span.End()
	}

	return nil
}

// formatCmd formats a Redis command and its arguments for db.statement
func formatCmd(cmd redis.Cmder) string {
	args := cmd.Args()
	formattedArgs := make([]string, len(args))

	for i, arg := range args {
		switch v := arg.(type) {
		case string:
			// For string arguments, use the string directly
			// Consider truncating long strings or masking sensitive data
			if len(v) > 100 {
				formattedArgs[i] = fmt.Sprintf("%s...", v[:100])
			} else {
				formattedArgs[i] = v
			}
		default:
			// For other types, use %v formatting
			formattedArgs[i] = fmt.Sprintf("%v", v)
		}
	}

	return strings.Join(formattedArgs, " ")
}
