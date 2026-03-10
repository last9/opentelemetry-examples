# frozen_string_literal: true

require 'otel_ruby_goodies/version'
require 'otel_ruby_goodies/configuration'
require 'otel_ruby_goodies/adapters'
require 'otel_ruby_goodies/railtie' if defined?(Rails::Railtie)

module OTelRubyGoodies
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def apply_env_configuration!(config = configuration)
      config.pg_slow_query_enabled =
        bool_env('OTEL_GOODIES_PG_SLOW_QUERY_ENABLED', config.pg_slow_query_enabled)
      config.pg_slow_query_threshold_ms =
        float_env('OTEL_GOODIES_PG_SLOW_QUERY_MS', float_env('OTEL_SLOW_QUERY_MS', config.pg_slow_query_threshold_ms))

      config.mysql2_slow_query_enabled =
        bool_env('OTEL_GOODIES_MYSQL2_SLOW_QUERY_ENABLED', config.mysql2_slow_query_enabled)
      config.mysql2_slow_query_threshold_ms =
        float_env('OTEL_GOODIES_MYSQL2_SLOW_QUERY_MS', config.mysql2_slow_query_threshold_ms)

      config.redis_source_enabled =
        bool_env('OTEL_GOODIES_REDIS_SOURCE_ENABLED', config.redis_source_enabled)
      config.clickhouse_enabled =
        bool_env('OTEL_GOODIES_CLICKHOUSE_ENABLED', config.clickhouse_enabled)
      config.clickhouse_slow_query_threshold_ms =
        float_env('OTEL_GOODIES_CLICKHOUSE_SLOW_QUERY_MS', config.clickhouse_slow_query_threshold_ms)

      config
    end

    def float_env(key, default)
      value = ENV[key]
      return default if value.nil? || value.strip.empty?

      Float(value)
    rescue ArgumentError, TypeError
      default
    end

    def bool_env(key, default)
      value = ENV[key]
      return default if value.nil? || value.strip.empty?

      return true if %w[1 true yes on].include?(value.strip.downcase)
      return false if %w[0 false no off].include?(value.strip.downcase)

      default
    end
  end
end
