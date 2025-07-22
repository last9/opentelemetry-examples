require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

class OtelSetup
  def initialize
    @otel_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new
    @processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(@otel_exporter)
  end

  def process
    OpenTelemetry::SDK.configure do |c|
      # Exporter and Processor configuration
      c.add_span_processor(@processor) # Created above this SDK.configure block

      # Resource configuration
      c.resource = OpenTelemetry::SDK::Resources::Resource.create({
                                                                    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => "staging" # Change to deployment environment
                                                                  })

      c.use_all() # enables all instrumentation!
    end
  end
end

OtelSetup.new.process
