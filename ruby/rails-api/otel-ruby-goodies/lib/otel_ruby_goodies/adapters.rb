# frozen_string_literal: true

require 'otel_ruby_goodies/adapters/pg'
require 'otel_ruby_goodies/adapters/mysql2'
require 'otel_ruby_goodies/adapters/redis'
require 'otel_ruby_goodies/adapters/clickhouse'

module OTelRubyGoodies
  module Adapters
    module_function

    def install!(app_root:, config: OTelRubyGoodies.configuration)
      install_pg!(app_root: app_root, config: config)
      install_mysql2!(app_root: app_root, config: config)
      install_redis!(app_root: app_root, config: config)
      install_clickhouse!(app_root: app_root, config: config)
    end

    def install_pg!(app_root:, config:)
      return unless config.pg_slow_query_enabled

      PG.install!(app_root: app_root, threshold_ms: config.pg_slow_query_threshold_ms)
    end

    def install_mysql2!(app_root:, config:)
      return unless config.mysql2_slow_query_enabled

      Mysql2.install!(app_root: app_root, threshold_ms: config.mysql2_slow_query_threshold_ms)
    end

    def install_redis!(app_root:, config:)
      return unless config.redis_source_enabled

      Redis.install!(app_root: app_root)
    end

    def install_clickhouse!(app_root:, config:)
      return unless config.clickhouse_enabled

      Clickhouse.install!(app_root: app_root, threshold_ms: config.clickhouse_slow_query_threshold_ms)
    end
  end
end
