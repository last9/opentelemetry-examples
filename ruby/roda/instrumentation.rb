require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'roda-api-service'
  c.use_all('OpenTelemetry::Instrumentation::Rack' => {
              url_quantization: -> (path, env) {
      # drop query params from path, as we don't need them for span name
      # otherwise span name will be too long and messy
      path = path.split('?').first
      path_parts = path.split('/')
      quantized_path = path_parts.map.with_index do |part, index|
        if index > 0
          case part
          when /\A\d+\z/
            ":id"  # Supports: /user/123 -> /user/:id
          when /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
            ":uuid"  # Supports: /user/550e8400-e29b-41d4-a716-446655440000 -> /user/:uuid
          else
            part  # Keeps other path parts unchanged: /api/v1/users -> /api/v1/users
          end
        else
          part  # Keeps the root path unchanged: / -> /
        end
      end.join('/')
      
      # Examples of supported transformations for request path to span name:
      
      # /user/123 -> /user/:id 
      # /api/v1/posts/abcd-1234-5678-efgh -> /api/v1/posts/:uuid
      # /products/456/reviews/789 -> /products/:id/reviews/:id
      # /categories/electronics/items/101 -> /categories/electronics/items/:id
      
      "#{env['REQUEST_METHOD']} #{quantized_path}"
    }
  })
end
