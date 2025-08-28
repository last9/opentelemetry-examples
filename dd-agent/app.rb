require 'sinatra'
require 'ddtrace'
require 'net/http'
require 'json'

# Configure DataDog tracer
Datadog.configure do |c|
  c.tracing.instrument :sinatra
  c.tracing.instrument :http
end

# Hello world endpoint that calls a third-party API
get '/hello' do
  content_type :json
  
  begin
    # Make a call to a third-party API (using JSONPlaceholder as an example)
    uri = URI('https://jsonplaceholder.typicode.com/posts/1')
    response = Net::HTTP.get_response(uri)
    
    {
      message: 'Hello World!',
      third_party_data: JSON.parse(response.body)
    }.to_json
  rescue StandardError => e
    status 500
    { error: 'Failed to fetch data from third-party API' }.to_json
  end
end

# Health check endpoint
get '/health' do
  status 200
  { status: 'healthy' }.to_json
end 