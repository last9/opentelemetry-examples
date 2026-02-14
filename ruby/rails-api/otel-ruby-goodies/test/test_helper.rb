# frozen_string_literal: true

require 'minitest/autorun'
require 'opentelemetry-api'
require 'logger'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'otel_ruby_goodies'

class FakeSpan
  attr_reader :attributes

  def initialize
    @attributes = {}
  end

  def set_attribute(key, value)
    @attributes[key] = value
  end
end

module EnvHelpers
  def with_env(vars)
    previous = {}
    vars.each do |key, value|
      previous[key] = ENV.key?(key) ? ENV[key] : :__unset__
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    previous.each do |key, value|
      value == :__unset__ ? ENV.delete(key) : ENV[key] = value
    end
  end
end

module SpanHelpers
  def with_current_span(fake_span = FakeSpan.new)
    singleton = OpenTelemetry::Trace.singleton_class
    singleton.class_eval do
      alias_method :__otel_goodies_original_current_span, :current_span
      define_method(:current_span) { fake_span }
    end

    yield fake_span
  ensure
    singleton.class_eval do
      alias_method :current_span, :__otel_goodies_original_current_span
      remove_method :__otel_goodies_original_current_span
    end
  end
end
