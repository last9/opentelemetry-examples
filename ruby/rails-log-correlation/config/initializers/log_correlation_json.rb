# frozen_string_literal: true

# Log-Trace Correlation: Custom JSON Formatter Example
# This initializer is loaded when LOG_CORRELATION_MODE=json

return unless ENV['LOG_CORRELATION_MODE'] == 'json'

Rails.application.configure do
  # Custom JSON formatter that includes trace context
  class JSONLogFormatter < Logger::Formatter
    def call(severity, timestamp, progname, msg)
      span = OpenTelemetry::Trace.current_span
      context = span.context

      log_entry = {
        timestamp: timestamp.utc.iso8601,
        level: severity,
        message: msg.to_s,
        progname: progname,
        trace_id: context.hex_trace_id,
        span_id: context.hex_span_id,
        pid: Process.pid
      }

      "#{log_entry.to_json}\n"
    end
  end

  # Apply the custom formatter to Rails logger
  config.logger = ActiveSupport::Logger.new(STDOUT)
  config.logger.formatter = JSONLogFormatter.new

  Rails.logger.info "✓ Log-Trace Correlation: JSON Formatter mode activated"
end
