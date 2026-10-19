# frozen_string_literal: true

require "sinatra"
require "json"
require_relative "instrumentation"

set :bind, "0.0.0.0"
set :port, 4567

DEFAULT_MODEL = ENV.fetch("DEMO_MODEL", "gpt-4o-mini")

get "/" do
  content_type :text
  <<~TXT
    ruby-llm-otel demo. Endpoints:
      POST /chat       — body: {"prompt": "..."}; returns model response and trace_id
      GET  /health     — liveness
      GET  /            — this help
  TXT
end

get "/health" do
  content_type :json
  { status: "ok", model: DEFAULT_MODEL }.to_json
end

post "/chat" do
  content_type :json

  body = request.body.read
  payload = body.empty? ? {} : JSON.parse(body)
  prompt = payload["prompt"] || "Say hello in five words or fewer."
  model = payload["model"] || DEFAULT_MODEL
  temperature = payload["temperature"] || 0.7

  # Wrap the chat in an outer named span so the trace ID is reachable in
  # the response for backend lookup. The ruby-llm-otel patch will create
  # a child `chat <model>` span when ruby_llm dispatches the provider
  # call.
  tracer = OpenTelemetry.tracer_provider.tracer("ruby-llm-otel-demo")
  response = nil
  trace_id = nil

  tracer.in_span("demo.chat") do |span|
    trace_id = span.context.hex_trace_id
    chat = RubyLLM.chat(model: model).with_temperature(temperature)
    response = chat.ask(prompt)
  end

  {
    model: model,
    trace_id: trace_id,
    tokens: {
      input: response.input_tokens,
      output: response.output_tokens
    },
    cost_usd: response.cost&.total,
    response: response.content
  }.to_json
rescue StandardError => e
  status 500
  { error: e.class.name, message: e.message, trace_id: trace_id }.to_json
end
