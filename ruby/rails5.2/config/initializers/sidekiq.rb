# Sidekiq + OpenTelemetry initialization
#
# opentelemetry-instrumentation-sidekiq (included via opentelemetry-instrumentation-all)
# auto-instruments Sidekiq via middleware when use_all() runs at Rails boot.
#
# This file handles two concerns:
#   1. Ensuring the OTel SDK shuts down cleanly when Sidekiq stops (flushes pending spans)
#   2. Providing a place to configure queue/job-level filtering via env vars:
#
#      OTEL_FILTER_SIDEKIQ_QUEUES — drop all spans from these queues (e.g. mailers,low)
#      OTEL_FILTER_SIDEKIQ_JOBS   — drop all spans from these job classes (e.g. HeartbeatJob)

if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    # Flush and shut down the OTel SDK when Sidekiq receives a stop signal.
    # Without this, spans buffered in the BatchSpanProcessor may be lost on shutdown.
    config.on(:shutdown) do
      OpenTelemetry.tracer_provider.shutdown
    end
  end
end
