require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'ruby-on-rails-api-service'

  config = {'OpenTelemetry::Instrumentation::fs' => { enabled: false }}
  c.use_all(config) # enables all instrumentation!
end
