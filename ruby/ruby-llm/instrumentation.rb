# frozen_string_literal: true

# OpenTelemetry SDK + ruby-llm-otel wiring. Required from app.rb before
# any RubyLLM.chat call so the patch is prepended.

require "dotenv/load"
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "ruby_llm"
require "ruby_llm/otel"

# Configure RubyLLM with the OpenAI key from env. The gem under test
# hooks Provider#complete, not the HTTP layer — so the key never reaches
# anything except OpenAI.
RubyLLM.configure do |c|
  c.openai_api_key = ENV.fetch("OPENAI_API_KEY")
end

use_console_exporter = ENV["USE_CONSOLE_EXPORTER"] == "1"
capture_message_content = ENV["CAPTURE_MESSAGE_CONTENT"] == "1"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "ruby-llm-otel-demo")

  if use_console_exporter
    # Local verification — print spans to stdout. Useful when you don't
    # want to ship traces to a real OTLP endpoint.
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      )
    )
  end
  # When USE_CONSOLE_EXPORTER is unset, the SDK auto-loads the OTLP
  # exporter from OTEL_EXPORTER_OTLP_ENDPOINT / OTEL_EXPORTER_OTLP_HEADERS.

  # Install the ruby-llm-otel instrumentation. The option name matches
  # OTel Python's capture_message_content so cross-language fleets share
  # one runbook.
  c.use "OpenTelemetry::Instrumentation::RubyLLM",
        { capture_message_content: capture_message_content }
end
