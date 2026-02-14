# frozen_string_literal: true

require 'test_helper'

class OTelRubyGoodiesIntegrationTest < ActiveSupport::TestCase
  def test_clickhouse_adapter_patches_connection_class_in_app_boot
    require 'click_house'

    klass = ::ClickHouse::Connection
    methods = OTelRubyGoodies::Adapters::Clickhouse::CANDIDATE_METHODS.select do |method_name|
      klass.instance_methods.include?(method_name)
    end

    assert_includes methods, :execute

    patch_module = OTelRubyGoodies::Adapters::Clickhouse.patch_module_for(klass, methods)
    assert klass.ancestors.include?(patch_module)
  end
end
