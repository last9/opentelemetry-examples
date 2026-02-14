# OpenTelemetry Exception Tracking for Rails 5.x
#
# This file fixes two known issues:
#
# 1. opentelemetry-instrumentation-action_pack v0.4.x doesn't record controller
#    exceptions as span events.
#    Bug: https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/635
#
# 2. opentelemetry-instrumentation-sidekiq's process_one patch wraps job execution
#    in `untraced`, which suppresses span recording when jobs lack propagated trace
#    context (no traceparent header). This causes NonRecordingSpan to be created,
#    so exceptions are silently dropped.
#
# INSTALLATION:
#   1. Copy this file to config/initializers/otel_exception_tracking.rb
#   2. Ensure OpenTelemetry is configured BEFORE this file loads
#      (rename to z_otel_exception_tracking.rb if needed for load order)
#   3. No other code changes required - exceptions are automatically captured
#
# COMPATIBILITY:
#   - Rails 5.0+ (tested with 5.2)
#   - Ruby 2.5+
#   - opentelemetry-sdk 1.0+
#   - opentelemetry-instrumentation-sidekiq 0.22+

module OtelExceptionTracking
  class << self
    # Record an exception on the current OTel span
    # Can also be called manually: OtelExceptionTracking.record(exception)
    def record(exception)
      span = ::OpenTelemetry::Trace.current_span
      return unless span && span.recording?

      span.record_exception(exception)
      span.status = ::OpenTelemetry::Trace::Status.error(exception.message)
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

  # Sidekiq server middleware that clears the untraced suppression flag.
  #
  # The sidekiq instrumentation gem wraps process_one in `untraced` to suppress
  # spans from Sidekiq's internal polling. But when a job has no propagated trace
  # context, the tracer_middleware inherits the suppressed context and creates a
  # NonRecordingSpan. This middleware resets to a clean root context so job spans
  # are always recorded and exported.
  class SidekiqClearUntraced
    def call(worker, msg, queue)
      if ::OpenTelemetry::Common::Utilities.untraced?
        # Replace the suppressed context with a clean root context.
        # This is safe because the OTel tracer_middleware (which runs next)
        # replaces the context anyway via Context.with_current(extracted_context).
        ::OpenTelemetry::Context.with_current(::OpenTelemetry::Context::ROOT) do
          yield
        end
      else
        yield
      end
    end
  end
end

# --- Rails / Rack setup ---

Rails.application.config.middleware.insert_before(
  ActionDispatch::ShowExceptions,
  OtelExceptionTracking::Middleware
)

ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  exception = event.payload[:exception_object]
  OtelExceptionTracking.record(exception) if exception
end

# --- Sidekiq setup ---

if defined?(::Sidekiq)
  ::Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      if defined?(::OpenTelemetry::Instrumentation::Sidekiq::Middlewares::Server::TracerMiddleware)
        chain.insert_before(
          ::OpenTelemetry::Instrumentation::Sidekiq::Middlewares::Server::TracerMiddleware,
          OtelExceptionTracking::SidekiqClearUntraced
        )
      else
        chain.prepend(OtelExceptionTracking::SidekiqClearUntraced)
      end
    end
  end
end

Rails.logger.info('[OTel Exception Tracking] Installed for Rails 5.x')
