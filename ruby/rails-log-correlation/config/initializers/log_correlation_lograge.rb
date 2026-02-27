# frozen_string_literal: true

# Log-Trace Correlation: Lograge (Structured Logging) Example
# This initializer is loaded when LOG_CORRELATION_MODE=lograge
# Requires: gem 'lograge'

return unless ENV['LOG_CORRELATION_MODE'] == 'lograge'

Rails.application.configure do
  # Enable Lograge for structured logging
  config.lograge.enabled = true

  # Format output as JSON
  config.lograge.formatter = Lograge::Formatters::Json.new

  # Add trace context to every log entry
  config.lograge.custom_options = lambda do |event|
    span = OpenTelemetry::Trace.current_span
    context = span.context

    {
      trace_id: context.hex_trace_id,
      span_id: context.hex_span_id,
      host: event.payload[:host],
      remote_ip: event.payload[:remote_ip],
      params: event.payload[:params].except('controller', 'action')
    }
  end

  Rails.logger.info "✓ Log-Trace Correlation: Lograge mode activated"
end
