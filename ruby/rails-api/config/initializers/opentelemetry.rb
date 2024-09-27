require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

# Exporter and Processor configuration
otel_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new
processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otel_exporter)

OpenTelemetry::SDK.configure do |c|
  # Exporter and Processor configuration
  c.add_span_processor(processor) # Created above this SDK.configure block

  # Resource configuration
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME => 'ruby-on-rails-api-service',
    OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => "0.0.0",
    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => Rails.env.to_s
  })

  c.use_all() # enables all instrumentation!
end
