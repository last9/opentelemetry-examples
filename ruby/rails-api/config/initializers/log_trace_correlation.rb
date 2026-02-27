# frozen_string_literal: true

# Log-Trace Correlation: Rails Logger Example
# Adds trace_id and span_id to all log messages

Rails.application.configure do
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

  Rails.logger.extend(LogTraceCorrelation)
  Rails.logger.info "✓ Log-Trace Correlation activated"
end
