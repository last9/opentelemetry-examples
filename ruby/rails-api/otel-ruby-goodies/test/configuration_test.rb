# frozen_string_literal: true

require_relative 'test_helper'

class ConfigurationTest < Minitest::Test
  include EnvHelpers

  def setup
    OTelRubyGoodies.reset_configuration!
  end

  def test_apply_env_configuration
    with_env(
      'OTEL_GOODIES_PG_SLOW_QUERY_ENABLED' => 'false',
      'OTEL_GOODIES_PG_SLOW_QUERY_MS' => '450.5',
      'OTEL_GOODIES_MYSQL2_SLOW_QUERY_ENABLED' => 'true',
      'OTEL_GOODIES_MYSQL2_SLOW_QUERY_MS' => '600',
      'OTEL_GOODIES_REDIS_SOURCE_ENABLED' => 'true',
      'OTEL_GOODIES_CLICKHOUSE_ENABLED' => 'false',
      'OTEL_GOODIES_CLICKHOUSE_SLOW_QUERY_MS' => '700'
    ) do
      config = OTelRubyGoodies.apply_env_configuration!

      assert_equal false, config.pg_slow_query_enabled
      assert_equal 450.5, config.pg_slow_query_threshold_ms
      assert_equal true, config.mysql2_slow_query_enabled
      assert_equal 600.0, config.mysql2_slow_query_threshold_ms
      assert_equal true, config.redis_source_enabled
      assert_equal false, config.clickhouse_enabled
      assert_equal 700.0, config.clickhouse_slow_query_threshold_ms
    end
  end

  def test_legacy_slow_query_env_is_supported_for_pg
    with_env(
      'OTEL_GOODIES_PG_SLOW_QUERY_MS' => nil,
      'OTEL_SLOW_QUERY_MS' => '275'
    ) do
      config = OTelRubyGoodies.apply_env_configuration!
      assert_equal 275.0, config.pg_slow_query_threshold_ms
    end
  end

  def test_invalid_values_fall_back_to_defaults
    with_env(
      'OTEL_GOODIES_PG_SLOW_QUERY_ENABLED' => 'invalid',
      'OTEL_GOODIES_PG_SLOW_QUERY_MS' => 'bad-number'
    ) do
      config = OTelRubyGoodies.apply_env_configuration!
      assert_equal true, config.pg_slow_query_enabled
      assert_equal 200.0, config.pg_slow_query_threshold_ms
      assert_equal true, config.mysql2_slow_query_enabled
      assert_equal true, config.clickhouse_enabled
    end
  end
end
