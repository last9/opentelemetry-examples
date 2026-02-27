# frozen_string_literal: true

# Log-Trace Correlation: Standard Rails Logger Example
# This initializer is loaded when LOG_CORRELATION_MODE=rails_logger (or not set)

return unless ENV.fetch('LOG_CORRELATION_MODE', 'rails_logger') == 'rails_logger'

Rails.application.configure do
  # Module to add trace context to Rails logger
  module LogTraceCorrelation
    def add(severity, message = nil, progname = nil)
      if block_given?
        super(severity, progname) do
          span = OpenTelemetry::Trace.current_span
          context = span.context
          "trace_id=#{context.hex_trace_id} span_id=#{context.hex_span_id} #{yield}"
        end
      else
        span = OpenTelemetry::Trace.current_span
        context = span.context
        super(severity, "trace_id=#{context.hex_trace_id} span_id=#{context.hex_span_id} #{message}", progname)
      end
    end
  end

  # Extend Rails logger with trace correlation
  Rails.logger.extend(LogTraceCorrelation)

  Rails.logger.info "✓ Log-Trace Correlation: Rails Logger mode activated"
end
