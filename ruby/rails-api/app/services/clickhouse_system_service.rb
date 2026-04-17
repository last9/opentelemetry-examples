# frozen_string_literal: true

# Wraps ClickHouse queries behind a service boundary.
#
# Includes RailsOtelContext::Frameable so every ClickHouse span created
# inside with_otel_frame carries:
#
#   code.namespace: "ClickhouseSystemService"
#   code.function:  <method name>
#
# Combined with span_name_formatter, the span is renamed from the raw
# "SELECT tables" to "ClickhouseSystemService.tables", mirroring how
# ActiveRecord spans are renamed to "OrderAnalyticsService.revenue_summary".
class ClickhouseSystemService
  include RailsOtelContext::Frameable

  CH = ClickHouse.connection

  def tables
    with_otel_frame do
      CH.select_all(
        "SELECT name, engine FROM system.tables WHERE database = 'system' LIMIT 10"
      ).to_a
    end
  end

  def columns
    with_otel_frame do
      CH.select_all(
        "SELECT table, name, type FROM system.columns WHERE database = 'system' LIMIT 10"
      ).to_a
    end
  end

  def databases
    with_otel_frame do
      CH.select_all('SELECT name, engine FROM system.databases').to_a
    end
  end

  def summary
    with_otel_frame do
      table_count = CH.select_value(
        "SELECT count() FROM system.tables WHERE database = 'system'"
      )
      settings = CH.select_all(
        "SELECT name, value FROM system.settings WHERE name LIKE 'max_%' LIMIT 5"
      ).to_a
      { system_table_count: table_count, sample_settings: settings }
    end
  end

  def one_table
    with_otel_frame do
      CH.select_one(
        "SELECT name, engine FROM system.tables WHERE database = 'system' ORDER BY name LIMIT 1"
      )
    end
  end

  # CH.insert — high-level API, internally calls insert_rows or insert_compact → execute.
  def insert_event(id:, name:)
    with_otel_frame do
      CH.insert('otel_test_events', values: [{ id: id, name: name }])
    end
  end

  # CH.insert_rows — exercises the format: keyword arg path through execute.
  def insert_rows_event(id:, name:)
    with_otel_frame do
      CH.insert_rows('otel_test_events', [{ id: id, name: name }], format: 'JSONEachRow')
    end
  end

  # CH.insert_compact — exercises columns:/values:/format: keyword args through execute.
  def insert_compact_event(id:, name:)
    with_otel_frame do
      CH.insert_compact('otel_test_events', columns: %w[id name], values: [[id, name]], format: 'JSONCompactEachRow')
    end
  end
end
