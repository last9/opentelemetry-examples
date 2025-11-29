# OpenTelemetry Configuration
# This initializer sets up OpenTelemetry instrumentation for Rails
# It configures automatic tracing for Rails components and sends data to Last9

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

# Configure OTLP exporter to send traces to Last9
otel_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new

# Set up batch processing for efficient trace export
processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otel_exporter)

# Configure OpenTelemetry SDK
OpenTelemetry::SDK.configure do |c|
  # Add the span processor for exporting traces
  c.add_span_processor(processor)

  # Configure resource attributes for better trace identification
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    # Service name from environment variable or default
    OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME => ENV['OTEL_SERVICE_NAME'] || 'ruby-on-rails-api-service',

    # Version of your service (update this with your app version)
    OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => "0.0.0",

    # Deployment environment (development, staging, production)
    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => Rails.env.to_s
  })

  # Enable all available instrumentations
  # This includes Rails, ActiveRecord, ActiveJob, ActionPack, and more
  c.use_all()
end

Rails.logger.info "OpenTelemetry initialized for #{Rails.env} environment"