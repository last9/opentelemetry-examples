# frozen_string_literal: true

# Skip if already configured (e.g., test environment sets up its own exporter).
return if defined?(OTEL_TRACER)

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/aws_lambda'
require 'opentelemetry/instrumentation/aws_sdk'

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'ruby-lambda')
  c.use 'OpenTelemetry::Instrumentation::AwsLambda'
  c.use 'OpenTelemetry::Instrumentation::AwsSdk'
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new
    )
  )
end

OTEL_TRACER = OpenTelemetry.tracer_provider.tracer(
  ENV.fetch('OTEL_SERVICE_NAME', 'ruby-lambda'),
  '1.0.0'
)
