require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

otel_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new
batch_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otel_exporter)

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(batch_processor)

  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME =>
      ENV.fetch('OTEL_SERVICE_NAME', 'ruby-on-rails-api-service'),
    OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => "0.5.0",
    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT =>
      ENV.fetch('OTEL_DEPLOYMENT_ENVIRONMENT', Rails.env.to_s)
  })

  c.use_all('OpenTelemetry::Instrumentation::Rack' => { use_rack_events: false })
end
# RailsOtelContext is configured in config/initializers/rails_otel_context.rb
