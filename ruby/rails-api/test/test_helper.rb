# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

# Add an in-memory span processor alongside the existing ones rather than
# replacing the SDK config. Replacing it via SDK.configure would create a new
# TracerProvider, breaking all instrumentation that cached their tracer at
# boot time (they'd create no-op spans with invalid contexts).
#
# SimpleSpanProcessor flushes synchronously so spans are available for
# assertion immediately after the request returns.
SPAN_EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry.tracer_provider.add_span_processor(
  OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(SPAN_EXPORTER)
)
