# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

class Mysql2AdapterTest < Minitest::Test
  include SpanHelpers

  ValidContext = Struct.new(:valid?)

  def setup
    OTelRubyGoodies::Adapters::Mysql2.instance_variable_set(:@patch_module, nil)
  end

  def test_query_sets_source_attributes_for_slow_queries
    patch = OTelRubyGoodies::Adapters::Mysql2.send(:build_patch_module)
    patch.configure(app_root: Dir.pwd, threshold_ms: 0.0)

    client_class = new_client_class
    client_class.prepend(patch)
    client = client_class.new

    with_thread_source('/app/services/payment.rb', 33) do
      with_current_span_with_valid_context do |span|
        result = client.query('SELECT 1')
        assert_equal :ok_query, result
        assert_equal 'app/services/payment.rb', span.attributes['code.filepath']
        assert_equal 33, span.attributes['code.lineno']
        assert span.attributes.key?('db.query.duration_ms')
        assert_equal 0.0, span.attributes['db.query.slow_threshold_ms']
      end
    end
  end

  def test_prepare_sets_source_attributes_for_slow_queries
    patch = OTelRubyGoodies::Adapters::Mysql2.send(:build_patch_module)
    patch.configure(app_root: Dir.pwd, threshold_ms: 0.0)

    client_class = new_client_class
    client_class.prepend(patch)
    client = client_class.new

    with_thread_source('/app/services/payment.rb', 44) do
      with_current_span_with_valid_context do |span|
        result = client.prepare('SELECT ?')
        assert_equal :ok_prepare, result
        assert_equal 'app/services/payment.rb', span.attributes['code.filepath']
        assert_equal 44, span.attributes['code.lineno']
      end
    end
  end

  def test_query_skips_attributes_for_fast_queries
    patch = OTelRubyGoodies::Adapters::Mysql2.send(:build_patch_module)
    patch.configure(app_root: Dir.pwd, threshold_ms: 999_999.0)

    client_class = new_client_class
    client_class.prepend(patch)
    client = client_class.new

    with_thread_source('/app/services/payment.rb', 22) do
      with_current_span_with_valid_context do |span|
        client.query('SELECT 1')
        refute span.attributes.key?('code.filepath')
        refute span.attributes.key?('code.lineno')
      end
    end
  end

  private

  def new_client_class
    Class.new do
      def query(_sql, _options = {})
        :ok_query
      end

      def prepare(_sql)
        :ok_prepare
      end
    end
  end

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

  def with_current_span_with_valid_context
    fake_span = FakeSpan.new
    fake_span.define_singleton_method(:context) { ValidContext.new(true) }

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
