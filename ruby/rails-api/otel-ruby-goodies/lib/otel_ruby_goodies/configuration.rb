# frozen_string_literal: true

module OTelRubyGoodies
  class Configuration
    attr_accessor :pg_slow_query_enabled,
                  :pg_slow_query_threshold_ms,
                  :mysql2_slow_query_enabled,
                  :mysql2_slow_query_threshold_ms,
                  :redis_source_enabled,
                  :clickhouse_enabled,
                  :clickhouse_slow_query_threshold_ms

    def initialize
      @pg_slow_query_enabled = true
      @pg_slow_query_threshold_ms = 200.0
      @mysql2_slow_query_enabled = true
      @mysql2_slow_query_threshold_ms = 200.0
      @redis_source_enabled = false
      @clickhouse_enabled = true
      @clickhouse_slow_query_threshold_ms = 200.0
    end
  end
end
