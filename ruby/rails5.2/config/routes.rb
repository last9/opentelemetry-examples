Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  # Test endpoints for OpenTelemetry tracing
  get '/health', to: 'test#health'
  get '/users', to: 'test#users'
  get '/calculate', to: 'test#calculate'
  get '/error', to: 'test#error'
  post '/process_order', to: 'test#process_order'
  get '/external_api', to: 'test#external_api'

  # Root path
  root 'test#health'
end
