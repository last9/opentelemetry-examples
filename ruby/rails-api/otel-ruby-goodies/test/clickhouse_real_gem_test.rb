# frozen_string_literal: true

require_relative 'test_helper'

class ClickhouseRealGemTest < Minitest::Test
  def setup
    OTelRubyGoodies::Adapters::Clickhouse.instance_variable_set(:@patch_modules, nil)
  end

  def test_real_click_house_connection_is_patchable
    require 'click_house'

    klass = ::ClickHouse::Connection
    methods = OTelRubyGoodies::Adapters::Clickhouse::CANDIDATE_METHODS.select do |method_name|
      klass.instance_methods.include?(method_name)
    end

    assert_includes methods, :execute

    patch_module = OTelRubyGoodies::Adapters::Clickhouse.patch_module_for(klass, methods)
    refute klass.ancestors.include?(patch_module)

    OTelRubyGoodies::Adapters::Clickhouse.install!(app_root: Dir.pwd, threshold_ms: 200.0)

    assert klass.ancestors.include?(patch_module)
  end
end
