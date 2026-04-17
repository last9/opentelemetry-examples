# frozen_string_literal: true

# click_house's logging middleware calls CGI.parse; cgi is no longer auto-loaded in Ruby 3.3+
require 'cgi'

ClickHouse.config do |config|
  config.url      = ENV.fetch('CLICKHOUSE_URL', 'http://localhost:8123')
  config.username = ENV.fetch('CLICKHOUSE_USER', 'otel')
  config.password = ENV.fetch('CLICKHOUSE_PASSWORD', 'oteltest')
end

# Memory table used by INSERT demo endpoints.
# ENGINE = Memory: no persistence, reset on ClickHouse restart — ideal for examples.
begin
  ClickHouse.connection.execute(
    'CREATE TABLE IF NOT EXISTS otel_test_events (id UInt32, name String) ENGINE = Memory'
  )
rescue StandardError => e
  Rails.logger.warn("[ClickHouse] Test table setup failed: #{e.message}")
end
