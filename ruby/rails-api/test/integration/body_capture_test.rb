# frozen_string_literal: true

require "test_helper"

class BodyCaptureTest < ActionDispatch::IntegrationTest
  setup    { SPAN_EXPORTER.reset }
  teardown { SPAN_EXPORTER.reset }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns the outermost HTTP span created by OpenTelemetry::Instrumentation::Rack.
  def rack_span
    SPAN_EXPORTER.finished_spans.find { |s| s.attributes.key?("http.method") }
  end

  # ---------------------------------------------------------------------------
  # Request body
  # ---------------------------------------------------------------------------

  test "sets http.request.body on the Rack span" do
    post "/api/v1/public/echo",
         params:  '{"id":42}',
         headers: { "Content-Type" => "application/json" }

    assert_equal 200, response.status
    assert_equal '{"id":42}', rack_span.attributes["http.request.body"]
  end

  test "request body is still readable by the controller" do
    post "/api/v1/public/echo",
         params:  '{"id":42}',
         headers: { "Content-Type" => "application/json" }

    assert_equal '{"id":42}', JSON.parse(response.body)["echo"]
  end

  test "does not capture request body for excluded content type" do
    post "/api/v1/public/echo",
         params:  "plain text",
         headers: { "Content-Type" => "text/html" }

    refute rack_span.attributes.key?("http.request.body")
  end

  # ---------------------------------------------------------------------------
  # Response body
  # ---------------------------------------------------------------------------

  test "sets http.response.body on the Rack span" do
    post "/api/v1/public/echo",
         params:  '{"id":42}',
         headers: { "Content-Type" => "application/json" }

    assert rack_span.attributes.key?("http.response.body"),
           "expected http.response.body to be set on span"
  end

  # ---------------------------------------------------------------------------
  # Path filtering — /health matches DEFAULT_EXCLUDE_PATHS
  # ---------------------------------------------------------------------------

  test "skips body capture for excluded health path" do
    get "/health"

    assert_equal 200, response.status
    refute rack_span.attributes.key?("http.request.body")
    refute rack_span.attributes.key?("http.response.body")
  end
end
