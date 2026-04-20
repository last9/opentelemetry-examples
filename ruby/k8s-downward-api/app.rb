require 'sinatra'
require 'json'
require_relative 'instrumentation'

set :bind, '0.0.0.0'
set :port, 4567

get '/hello' do
  content_type :json
  { message: 'hello from k8s', pod: ENV['K8S_POD_NAME'] }.to_json
end

get '/health' do
  'ok'
end
