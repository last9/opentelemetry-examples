# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

class PgAdapterTest < Minitest::Test
  include SpanHelpers

  def setup
    OTelRubyGoodies::Adapters::PG.instance_variable_set(:@patch_module, nil)
  end

  def test_patch_sets_code_location_attributes_for_slow_queries
    patch = OTelRubyGoodies::Adapters::PG.send(:build_patch_module, [:exec])
    patch.configure(app_root: Dir.pwd, threshold_ms: 0.0)

    host_class = new_host_class
    host_class.prepend(patch)
    host = host_class.new

    with_thread_source('/app/models/checkout.rb', 88) do
      with_current_span do |span|
        host.exec('select 1')
        assert_equal 'app/models/checkout.rb', span.attributes['code.filepath']
        assert_equal 88, span.attributes['code.lineno']
        assert span.attributes.key?('db.query.duration_ms')
        assert_equal 0.0, span.attributes['db.query.slow_threshold_ms']
      end
    end
  end

  def test_patch_skips_attributes_for_fast_queries
    patch = OTelRubyGoodies::Adapters::PG.send(:build_patch_module, [:exec])
    patch.configure(app_root: Dir.pwd, threshold_ms: 999_999.0)

    host_class = new_host_class
    host_class.prepend(patch)
    host = host_class.new

    with_thread_source('/app/models/checkout.rb', 44) do
      with_current_span do |span|
        host.exec('select 1')
        refute span.attributes.key?('code.filepath')
        refute span.attributes.key?('code.lineno')
      end
    end
  end

  private

  def new_host_class
    Class.new do
      def exec(_sql)
        result = :ok
        block_given? ? yield(result) : result
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
end
