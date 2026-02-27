# frozen_string_literal: true

# Log-Trace Correlation: Semantic Logger Example
# This initializer is loaded when LOG_CORRELATION_MODE=semantic_logger
# Requires: gem 'rails_semantic_logger'

return unless ENV['LOG_CORRELATION_MODE'] == 'semantic_logger'

Rails.application.configure do
  # Semantic Logger will be configured via rails_semantic_logger gem

  # Add trace context to all log entries using named tags
  SemanticLogger.on_log do |log|
    span = OpenTelemetry::Trace.current_span
    context = span.context
    log.named_tags[:trace_id] = context.hex_trace_id
    log.named_tags[:span_id] = context.hex_span_id
  end

  Rails.logger.info "✓ Log-Trace Correlation: Semantic Logger mode activated"
end
