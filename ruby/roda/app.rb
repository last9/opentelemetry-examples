# app.rb
require 'roda'
require 'rack'
require_relative 'instrumentation'

class App < Roda
  route do |r|
    r.root do
      "Welcome to the Roda Example App!"
    end

    r.on "hello" do
      r.get "world" do
        "Hello, World!"
      end

      r.get String do |name|
        "Hello, #{name}!"
      end
    end
  end
end

App.use ::Rack::Events, [OpenTelemetry::Instrumentation::Rack::Middlewares::EventHandler.new]
