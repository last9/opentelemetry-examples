# frozen_string_literal: true

module Api
  module V1
    # Exercises rails-otel-context ClickHouse adapter end-to-end.
    #
    # Two sets of endpoints:
    #
    # Direct (controller calls ClickHouse) — span name reflects controller:
    #   GET /api/v1/clickhouse/tables    → "ClickhouseController.tables_list"
    #   GET /api/v1/clickhouse/multi     → N spans, each "ClickhouseController.multi_query"
    #
    # Via service (ClickhouseSystemService wraps queries with Frameable) — span
    # name reflects the service boundary instead:
    #   GET /api/v1/clickhouse/svc/tables    → "ClickhouseSystemService.tables"
    #   GET /api/v1/clickhouse/svc/summary   → "ClickhouseSystemService.summary"
    class ClickhouseController < ApplicationController
      CH = ClickHouse.connection

      # ── Direct (controller as call-site) ─────────────────────────────────

      # GET /api/v1/clickhouse/tables
      def tables_list
        rows = CH.select_all(
          "SELECT name, engine FROM system.tables WHERE database = 'system' LIMIT 10"
        ).to_a
        render json: { tables: rows, count: rows.size }
      end

      # GET /api/v1/clickhouse/columns
      def columns_list
        rows = CH.select_all(
          "SELECT table, name, type FROM system.columns WHERE database = 'system' LIMIT 10"
        ).to_a
        render json: { columns: rows, count: rows.size }
      end

      # GET /api/v1/clickhouse/databases
      def databases_list
        rows = CH.select_all('SELECT name, engine FROM system.databases').to_a
        render json: { databases: rows }
      end

      # GET /api/v1/clickhouse/one
      # Exercises select_one — returns first matching row as a Hash (nil if empty).
      def select_one_row
        row = CH.select_one(
          "SELECT name, engine FROM system.tables WHERE database = 'system' ORDER BY name LIMIT 1"
        )
        render json: { row: row }
      end

      # GET /api/v1/clickhouse/execute
      # Exercises execute directly with keyword args (database:) — validates kwargs forwarding.
      def execute_query
        response = CH.execute('SELECT count() FROM system.tables', nil, database: 'system')
        render json: { ok: response.success?, status: response.status }
      end

      # POST /api/v1/clickhouse/insert
      # Exercises CH.insert — high-level API, delegates to insert_rows or insert_compact → execute.
      def insert_row
        CH.insert(
          'otel_test_events',
          values: [{ id: rand(1..99_999), name: "otel-#{SecureRandom.hex(4)}" }]
        )
        render json: { ok: true, method: 'insert' }
      end

      # POST /api/v1/clickhouse/insert_rows
      # Exercises insert_rows directly with the format: keyword arg.
      # Verifies kwargs are forwarded through the execute intercept without ArgumentError.
      def insert_rows_direct
        CH.insert_rows(
          'otel_test_events',
          [{ id: rand(1..99_999), name: "rows-#{SecureRandom.hex(4)}" }],
          format: 'JSONEachRow'
        )
        render json: { ok: true, method: 'insert_rows' }
      end

      # POST /api/v1/clickhouse/insert_compact
      # Exercises insert_compact directly with columns: and values: keyword args.
      # Verifies kwargs are forwarded through the execute intercept without ArgumentError.
      def insert_compact_direct
        CH.insert_compact(
          'otel_test_events',
          columns: %w[id name],
          values:  [[rand(1..99_999), "compact-#{SecureRandom.hex(4)}"]],
          format:  'JSONCompactEachRow'
        )
        render json: { ok: true, method: 'insert_compact' }
      end

      # GET /api/v1/clickhouse/multi
      def multi_query
        tables = CH.select_all(
          "SELECT count() FROM system.tables WHERE database = 'system'"
        ).to_a
        processes = CH.select_all(
          'SELECT query_id, user, elapsed FROM system.processes LIMIT 5'
        ).to_a
        settings = CH.select_all(
          "SELECT name, value FROM system.settings WHERE name LIKE 'max_%' LIMIT 5"
        ).to_a
        render json: {
          system_table_count: tables.first&.values&.first,
          active_processes:   processes.size,
          sample_settings:    settings
        }
      end

      # ── Via ClickhouseSystemService (service as call-site) ────────────────
      #
      # All ClickHouse spans inside the service carry:
      #   code.namespace: "ClickhouseSystemService"
      #   code.function:  <method name>
      # and are renamed by span_name_formatter to "ClickhouseSystemService.<method>".

      # GET /api/v1/clickhouse/svc/tables
      def svc_tables
        svc = ClickhouseSystemService.new
        rows = svc.tables
        render json: { tables: rows, count: rows.size, via: 'ClickhouseSystemService' }
      end

      # GET /api/v1/clickhouse/svc/columns
      def svc_columns
        svc = ClickhouseSystemService.new
        rows = svc.columns
        render json: { columns: rows, count: rows.size, via: 'ClickhouseSystemService' }
      end

      # GET /api/v1/clickhouse/svc/databases
      def svc_databases
        svc = ClickhouseSystemService.new
        render json: { databases: svc.databases, via: 'ClickhouseSystemService' }
      end

      # GET /api/v1/clickhouse/svc/summary
      def svc_summary
        svc = ClickhouseSystemService.new
        render json: svc.summary.merge(via: 'ClickhouseSystemService')
      end

      # GET /api/v1/clickhouse/svc/one
      def svc_one
        svc = ClickhouseSystemService.new
        render json: { row: svc.one_table, via: 'ClickhouseSystemService' }
      end

      # POST /api/v1/clickhouse/svc/insert
      def svc_insert
        svc = ClickhouseSystemService.new
        svc.insert_event(id: rand(1..99_999), name: "svc-#{SecureRandom.hex(4)}")
        render json: { ok: true, method: 'insert', via: 'ClickhouseSystemService' }
      end

      # POST /api/v1/clickhouse/svc/insert_rows
      def svc_insert_rows
        svc = ClickhouseSystemService.new
        svc.insert_rows_event(id: rand(1..99_999), name: "svc-rows-#{SecureRandom.hex(4)}")
        render json: { ok: true, method: 'insert_rows', via: 'ClickhouseSystemService' }
      end

      # POST /api/v1/clickhouse/svc/insert_compact
      def svc_insert_compact
        svc = ClickhouseSystemService.new
        svc.insert_compact_event(id: rand(1..99_999), name: "svc-compact-#{SecureRandom.hex(4)}")
        render json: { ok: true, method: 'insert_compact', via: 'ClickhouseSystemService' }
      end
    end
  end
end
