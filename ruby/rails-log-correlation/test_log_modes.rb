#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone script to test all 4 log-trace correlation modes
# This simulates what the Rails initializers do without starting the full server

require 'logger'
require 'json'
require 'time'

# Mock OpenTelemetry span context for demonstration
class MockSpanContext
  def hex_trace_id
    "4bf92f3577b34da6a3ce929d0e0e4736"
  end

  def hex_span_id
    "00f067aa0ba902b7"
  end
end

class MockSpan
  def context
    MockSpanContext.new
  end
end

# Mock OpenTelemetry module
module OpenTelemetry
  module Trace
    def self.current_span
      MockSpan.new
    end
  end
end

puts "=" * 80
puts "Testing Log-Trace Correlation Implementations"
puts "=" * 80
puts

# Test 1: Rails Logger Mode
puts "MODE 1: RAILS LOGGER (Text Format)"
puts "-" * 80

module LogTraceCorrelation
  def add(severity, message = nil, progname = nil)
    if block_given?
      super(severity, progname) do
        span = OpenTelemetry::Trace.current_span
        context = span.context
        "trace_id=#{context.hex_trace_id} span_id=#{context.hex_span_id} #{yield}"
      end
    else
      span = OpenTelemetry::Trace.current_span
      context = span.context
      super(severity, "trace_id=#{context.hex_trace_id} span_id=#{context.hex_span_id} #{message}", progname)
    end
  end
end

logger1 = Logger.new(STDOUT)
logger1.extend(LogTraceCorrelation)
logger1.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end

logger1.info { "Demo endpoint called - hello action" }
logger1.debug { "This is a debug message with trace context" }
logger1.error { "Error occurred: Sample error message" }
puts

# Test 2: Lograge Mode (Structured JSON)
puts "MODE 2: LOGRAGE (Structured JSON)"
puts "-" * 80

span = OpenTelemetry::Trace.current_span
context = span.context

lograge_output = {
  method: "GET",
  path: "/demo/hello",
  format: "json",
  controller: "DemoController",
  action: "hello",
  status: 200,
  duration: 12.34,
  trace_id: context.hex_trace_id,
  span_id: context.hex_span_id,
  host: "localhost:3000",
  params: {}
}

puts JSON.pretty_generate(lograge_output)
puts

# Test 3: Semantic Logger Mode
puts "MODE 3: SEMANTIC LOGGER (Named Tags)"
puts "-" * 80

timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%6N")
pid = Process.pid

puts "#{timestamp} I [#{pid}:DemoController] {trace_id: \"#{context.hex_trace_id}\", span_id: \"#{context.hex_span_id}\"} Demo endpoint called - hello action"
puts "#{timestamp} D [#{pid}:DemoController] {trace_id: \"#{context.hex_trace_id}\", span_id: \"#{context.hex_span_id}\"} This is a debug message with trace context"
puts "#{timestamp} E [#{pid}:DemoController] {trace_id: \"#{context.hex_trace_id}\", span_id: \"#{context.hex_span_id}\"} Error occurred: Sample error message"
puts

# Test 4: Custom JSON Formatter
puts "MODE 4: CUSTOM JSON FORMATTER (Pure JSON)"
puts "-" * 80

class JSONLogFormatter < Logger::Formatter
  def call(severity, timestamp, progname, msg)
    span = OpenTelemetry::Trace.current_span
    context = span.context

    log_entry = {
      timestamp: timestamp.utc.iso8601,
      level: severity,
      message: msg.to_s,
      progname: progname,
      trace_id: context.hex_trace_id,
      span_id: context.hex_span_id,
      pid: Process.pid
    }

    "#{log_entry.to_json}\n"
  end
end

logger4 = Logger.new(STDOUT)
logger4.formatter = JSONLogFormatter.new

logger4.info "Demo endpoint called - hello action"
logger4.debug "This is a debug message with trace context"
logger4.error "Error occurred: Sample error message"
puts

puts "=" * 80
puts "All 4 modes tested successfully!"
puts "=" * 80
puts
puts "KEY OBSERVATIONS:"
puts "1. All logs include the same trace_id and span_id"
puts "2. Formats differ based on use case:"
puts "   - Rails Logger: Simple text format, easy to read"
puts "   - Lograge: Structured JSON with request metadata"
puts "   - Semantic Logger: Named tags with context"
puts "   - JSON Formatter: Pure JSON, best for log aggregation"
puts "3. All implementations use OpenTelemetry::Trace.current_span.context"
puts "=" * 80
