# OpenTelemetry Exception Tracking for Rails 5.x
#
# This file fixes a known bug in opentelemetry-instrumentation-action_pack v0.4.x
# where controller exceptions are not recorded as span events.
#
# Bug reference: https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/635
#
# INSTALLATION:
#   1. Copy this file to config/initializers/otel_exception_tracking.rb
#   2. Ensure OpenTelemetry is configured BEFORE this file loads
#      (rename to z_otel_exception_tracking.rb if needed for load order)
#   3. No other code changes required - exceptions are automatically captured
#
# WHAT IT DOES:
#   - Records exception details on the current OTel span when errors occur
#   - Adds exception.type, exception.message, exception.stacktrace as span event
#   - Sets span status to ERROR
#   - Captures BOTH:
#     * Unhandled exceptions (via Rack middleware)
#     * Handled exceptions via rescue_from (via ActiveSupport::Notifications)
#
# COMPATIBILITY:
#   - Rails 5.0+ (tested with 5.2)
#   - Ruby 2.5+
#   - opentelemetry-sdk 1.0+

module OtelExceptionTracking
  class << self
    # Record an exception on the current OTel span
    # Can also be called manually: OtelExceptionTracking.record(exception)
    def record(exception)
      span = OpenTelemetry::Trace.current_span
      return unless span && span.recording?

      span.record_exception(exception)
      span.status = OpenTelemetry::Trace::Status.error(exception.message)
    rescue => e
      Rails.logger.warn("[OTel Exception Tracking] Failed to record: #{e.message}")
    end
  end

  # Rack middleware for unhandled exceptions that bubble up
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Exception => e
      unless env['otel.exception_recorded']
        OtelExceptionTracking.record(e)
        env['otel.exception_recorded'] = true
      end
      raise
    end
  end
end

# Insert middleware directly (runs during initializer load)
Rails.application.config.middleware.insert_before(
  ActionDispatch::ShowExceptions,
  OtelExceptionTracking::Middleware
)

# Subscribe to notifications to catch handled exceptions (rescue_from)
ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  exception = event.payload[:exception_object]
  OtelExceptionTracking.record(exception) if exception
end

Rails.logger.info('[OTel Exception Tracking] Installed for Rails 5.x')
