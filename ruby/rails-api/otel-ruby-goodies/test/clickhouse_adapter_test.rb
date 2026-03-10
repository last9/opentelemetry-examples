# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

class ClickhouseAdapterTest < Minitest::Test
  include SpanHelpers

  def setup
    OTelRubyGoodies::Adapters::Clickhouse.instance_variable_set(:@patch_modules, nil)
  end

  def test_query_creates_span_with_slow_source_attributes
    patch = OTelRubyGoodies::Adapters::Clickhouse.send(:build_patch_module, [:query])
    patch.configure(app_root: Dir.pwd, threshold_ms: 0.0)

    client_class = Class.new do
      def query(_sql)
        :ok
      end
    end
    client_class.prepend(patch)

    with_thread_source('/app/services/warehouse.rb', 14) do
      with_tracer_spy do |calls|
        result = client_class.new.query('SELECT 1')
        assert_equal :ok, result
        assert_equal 1, calls.size
        span = calls[0]
        assert_equal 'QUERY clickhouse', span[:name]
        assert_equal :client, span[:kind]
        assert_equal 'clickhouse', span[:attributes]['db.system']
        assert_equal 'QUERY', span[:attributes]['db.operation']
        assert_equal 'SELECT 1', span[:attributes]['db.statement']
        assert_equal 'app/services/warehouse.rb', span[:attributes]['code.filepath']
        assert_equal 14, span[:attributes]['code.lineno']
      end
    end
  end

  def test_query_omits_slow_source_attributes_when_below_threshold
    patch = OTelRubyGoodies::Adapters::Clickhouse.send(:build_patch_module, [:query])
    patch.configure(app_root: Dir.pwd, threshold_ms: 999_999.0)

    client_class = Class.new do
      def query(_sql)
        :ok
      end
    end
    client_class.prepend(patch)

    with_thread_source('/app/services/warehouse.rb', 18) do
      with_tracer_spy do |calls|
        client_class.new.query('SELECT 1')
        span = calls[0]
        refute span[:attributes].key?('code.filepath')
        refute span[:attributes].key?('code.lineno')
      end
    end
  end

  private

  def with_thread_source(path, lineno)
    thread_singleton = Thread.singleton_class
    location = OpenStruct.new(absolute_path: File.join(Dir.pwd, path), path: nil, lineno: lineno)
    had_original = Thread.respond_to?(:each_caller_location)

    if had_original
      thread_singleton.class_eval do
        alias_method :__otel_goodies_original_each_caller_location, :each_caller_location
      end
    end
    thread_singleton.define_method(:each_caller_location) { |&block| block.call(location) }

    yield
  ensure
    if had_original
      thread_singleton.class_eval do
        alias_method :each_caller_location, :__otel_goodies_original_each_caller_location
        remove_method :__otel_goodies_original_each_caller_location
      end
    else
      thread_singleton.class_eval { remove_method :each_caller_location }
    end
  end

  def with_tracer_spy
    calls = []
    fake_tracer = Class.new do
      def initialize(calls)
        @calls = calls
      end

      def in_span(name, kind: nil)
        span = FakeSpan.new
        @calls << { name: name, kind: kind, attributes: span.attributes }
        yield span
      end
    end.new(calls)

    fake_provider = Class.new do
      def initialize(tracer)
        @tracer = tracer
      end

      def tracer(_name)
        @tracer
      end
    end.new(fake_tracer)

    singleton = OpenTelemetry.singleton_class
    singleton.class_eval do
      alias_method :__otel_goodies_original_tracer_provider, :tracer_provider
      define_method(:tracer_provider) { fake_provider }
    end

    yield calls
  ensure
    singleton.class_eval do
      alias_method :tracer_provider, :__otel_goodies_original_tracer_provider
      remove_method :__otel_goodies_original_tracer_provider
    end
  end
end
