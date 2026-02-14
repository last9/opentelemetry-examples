# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

class RedisAdapterTest < Minitest::Test
  def setup
    OTelRubyGoodies::Adapters::Redis.instance_variable_set(:@patch_module, nil)
  end

  def test_call_injects_source_attributes
    patch = OTelRubyGoodies::Adapters::Redis.send(:build_patch_module)
    patch.configure(app_root: Dir.pwd)

    middleware_class = new_middleware_class
    middleware_class.prepend(patch)
    middleware = middleware_class.new

    with_thread_source('/app/services/cache_service.rb', 21) do
      with_redis_with_attributes_spy do |calls|
        result = middleware.call(['GET', 'k'], Object.new) { :ok }
        assert_equal :ok, result
        assert_equal 1, calls.size
        assert_equal 'app/services/cache_service.rb', calls[0]['code.filepath']
        assert_equal 21, calls[0]['code.lineno']
      end
    end
  end

  def test_call_pipelined_injects_source_attributes
    patch = OTelRubyGoodies::Adapters::Redis.send(:build_patch_module)
    patch.configure(app_root: Dir.pwd)

    middleware_class = new_middleware_class
    middleware_class.prepend(patch)
    middleware = middleware_class.new

    with_thread_source('/app/services/cache_service.rb', 42) do
      with_redis_with_attributes_spy do |calls|
        result = middleware.call_pipelined([['SET', 'a', '1']], Object.new) { :ok }
        assert_equal :ok, result
        assert_equal 1, calls.size
        assert_equal 'app/services/cache_service.rb', calls[0]['code.filepath']
        assert_equal 42, calls[0]['code.lineno']
      end
    end
  end

  def test_call_skips_attributes_when_source_missing
    patch = OTelRubyGoodies::Adapters::Redis.send(:build_patch_module)
    patch.configure(app_root: '/unlikely/root')

    middleware_class = new_middleware_class
    middleware_class.prepend(patch)
    middleware = middleware_class.new

    with_redis_with_attributes_spy do |calls|
      result = middleware.call(['GET', 'k'], Object.new) { :ok }
      assert_equal :ok, result
      assert_equal 0, calls.size
    end
  end

  private

  def new_middleware_class
    Class.new do
      def call(command, _config)
        block_given? ? yield(command) : :ok
      end

      def call_pipelined(commands, _config)
        block_given? ? yield(commands) : :ok
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

  def with_redis_with_attributes_spy
    calls = []
    redis_mod = ensure_redis_instrumentation_module
    singleton = redis_mod.singleton_class

    singleton.class_eval do
      if method_defined?(:with_attributes)
        alias_method :__otel_goodies_original_with_attributes, :with_attributes
      end
    end

    singleton.define_method(:with_attributes) do |attrs, &block|
      calls << attrs
      block.call
    end

    yield calls
  ensure
    singleton.class_eval do
      if method_defined?(:__otel_goodies_original_with_attributes)
        alias_method :with_attributes, :__otel_goodies_original_with_attributes
        remove_method :__otel_goodies_original_with_attributes
      else
        remove_method :with_attributes
      end
    end
  end

  def ensure_redis_instrumentation_module
    open_telemetry = if defined?(::OpenTelemetry)
                       ::OpenTelemetry
                     else
                       Object.const_set(:OpenTelemetry, Module.new)
                     end
    instrumentation = if open_telemetry.const_defined?(:Instrumentation, false)
                        open_telemetry.const_get(:Instrumentation)
                      else
                        open_telemetry.const_set(:Instrumentation, Module.new)
                      end

    if instrumentation.const_defined?(:Redis, false)
      instrumentation.const_get(:Redis)
    else
      instrumentation.const_set(:Redis, Module.new)
    end
  end
end
