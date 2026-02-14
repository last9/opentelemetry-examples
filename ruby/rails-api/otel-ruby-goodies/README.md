# otel-ruby-goodies

Reusable OpenTelemetry Ruby patches maintained by Last9.

## Included adapters

- `pg` (implemented)
  - Adds `code.filepath` and `code.lineno` on slow PG spans.
  - Adds `db.query.duration_ms` and `db.query.slow_threshold_ms`.
- `mysql2` (implemented)
  - Adds `code.filepath` and `code.lineno` on slow MySQL2 spans.
  - Adds `db.query.duration_ms` and `db.query.slow_threshold_ms`.
- `redis` (implemented)
  - Adds `code.filepath` and `code.lineno` on Redis spans via Redis middleware attributes.
- `clickhouse` (implemented for common clients)
  - Creates client spans for `query/select/insert/execute/command` when ClickHouse client classes are present.
  - Adds slow-query source attributes using the ClickHouse threshold.

## Usage

Add the gem:

```ruby
gem 'otel-ruby-goodies', path: 'otel-ruby-goodies'
```

Set threshold in env (optional):

```bash
OTEL_SLOW_QUERY_MS=200
```

## Configuration

```ruby
OTelRubyGoodies.configure do |c|
  c.pg_slow_query_enabled = true
  c.pg_slow_query_threshold_ms = 200.0

  c.mysql2_slow_query_enabled = true
  c.mysql2_slow_query_threshold_ms = 200.0

  c.redis_source_enabled = false

  c.clickhouse_enabled = true
  c.clickhouse_slow_query_threshold_ms = 200.0
end
```

### Environment variables

- `OTEL_GOODIES_PG_SLOW_QUERY_ENABLED` (default: `true`)
- `OTEL_GOODIES_PG_SLOW_QUERY_MS` (default: `200.0`)
- `OTEL_SLOW_QUERY_MS` (legacy fallback for PG threshold)
- `OTEL_GOODIES_MYSQL2_SLOW_QUERY_ENABLED` (default: `true`)
- `OTEL_GOODIES_MYSQL2_SLOW_QUERY_MS` (default: `200.0`)
- `OTEL_GOODIES_REDIS_SOURCE_ENABLED` (default: `false`)
- `OTEL_GOODIES_CLICKHOUSE_ENABLED` (default: `true`)
- `OTEL_GOODIES_CLICKHOUSE_SLOW_QUERY_MS` (default: `200.0`)
