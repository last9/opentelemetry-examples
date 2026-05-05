require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'
require 'opentelemetry-logs-sdk'
require 'opentelemetry-exporter-otlp-logs'

resource_attrs = {
  OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME =>
    ENV.fetch('OTEL_SERVICE_NAME', 'stripe-payments-api'),
  OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => '1.0.0',
  OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT =>
    ENV.fetch('OTEL_DEPLOYMENT_ENVIRONMENT', Rails.env.to_s)
}

# ── Traces ────────────────────────────────────────────────────────────────────
otel_exporter   = OpenTelemetry::Exporter::OTLP::Exporter.new
batch_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otel_exporter)

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(batch_processor)
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(resource_attrs)

  # Also sets up the LoggerProvider via ConfiguratorPatch from opentelemetry-logs-sdk
  c.add_log_record_processor(
    OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
      OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new
    )
  )

  c.use_all()
end
