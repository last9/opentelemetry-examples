require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/sinatra'
require 'opentelemetry/instrumentation/rack'

# Resource attributes from OTEL_RESOURCE_ATTRIBUTES env var
# are merged automatically by the SDK. Downward API injects k8s.* attrs there.
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'ruby-k8s-demo')
  c.use 'OpenTelemetry::Instrumentation::Sinatra'
  c.use 'OpenTelemetry::Instrumentation::Rack'
end
