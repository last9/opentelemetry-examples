require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

# Custom SpanProcessor that adds service.namespace from request-scoped storage
class NamespaceSpanProcessor < OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor
  def on_start(span, parent_context)
    # Get namespace from request-scoped CurrentAttributes (not baggage)
    # CurrentRequest resets automatically between requests - no leakage
    namespace = CurrentRequest.service_namespace rescue nil
    span.set_attribute("service.namespace", namespace) if namespace
  end
end

# Exporter and Processor configuration
otel_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new
batch_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otel_exporter)
namespace_processor = NamespaceSpanProcessor.new(otel_exporter)

OpenTelemetry::SDK.configure do |c|
  # Add processors - namespace processor adds attributes, batch processor exports
  c.add_span_processor(namespace_processor)
  c.add_span_processor(batch_processor)

  # Resource configuration
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME => 'ruby-on-rails-api-service',
    OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => "0.0.0",
    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => Rails.env.to_s
  })

  c.use_all() # enables all instrumentation!
end
