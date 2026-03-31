module Api
  module V1
    class DemoController < ApplicationController
      # GET /api/v1/demo/complex_queries
      # Exercises all models with scopes, custom methods, joins, and associations
      def complex_queries
        results = {}

        # User queries
        results[:active_users] = User.active.count
        results[:signup_stats] = User.signup_stats
        results[:top_spenders] = User.top_spenders(3).map { |u| { name: u.name, spent: u.try(:total_spent) } }
        results[:admin_count] = User.admins.count
        results[:pro_users] = User.by_plan('pro').count

        # Order queries
        results[:recent_orders] = Order.recent.limit(5).map { |o| { number: o.order_number, total: o.total.to_f } }
        results[:completed_high_value] = Order.completed.high_value.count
        results[:avg_order_value] = Order.average_order_value.to_f.round(2)

        # OrderItem queries
        results[:best_sellers] = OrderItem.best_sellers(3)
        results[:expensive_items] = OrderItem.expensive.count

        # Transaction queries
        results[:recent_transactions] = Transaction.recent_completed.count
        results[:total_revenue] = Transaction.total_revenue.to_f.round(2)
        results[:failed_count] = Transaction.failed_count

        # Cross-model: eager load
        results[:users_with_orders] = User.includes(:orders).where(role: 'admin').map do |u|
          { name: u.name, order_count: u.orders.size }
        end

        render json: results
      end

      # GET /api/v1/demo/otel_v8_features
      #
      # Comprehensive E2E exercise of every rails-otel-context v0.8.0 feature.
      # Each section maps to a specific OTel attribute — see inline comments.
      #
      # What to verify in your OTel backend after hitting this endpoint:
      #
      #  FEATURE                        ATTRIBUTE TO CHECK
      #  ─────────────────────────────────────────────────────────────────────
      #  1. Controller frame push       code.namespace: "Api::V1::DemoController"
      #                                 code.function:  "otel_v8_features"
      #                                 (on ALL spans in this trace, set O(1))
      #
      #  2. Frameable — service object  code.namespace: "OrderAnalyticsService"
      #                                 code.function:  "revenue_summary"
      #                                 (on DB child spans inside that method)
      #
      #  3. Frameable — repository      code.namespace: "UserRepository"
      #                                 code.function:  "find_active_users"
      #                                 (on DB child spans inside the repo)
      #
      #  4. SQL-named span (UPDATE)     code.activerecord.model:  "Transaction"
      #                                 code.activerecord.method: "Update"
      #                                 (from update_all — fires name="SQL")
      #
      #  5. SQL-named span (SELECT)     code.activerecord.model:  "User"
      #                                 code.activerecord.method: "Select"
      #                                 (from connection.execute raw SELECT)
      #
      #  6. db.async                    db.async: true
      #                                 (on async_count spans)
      #
      #  7. N+1 detection               db.query_count: 2, 3, 4, 5
      #                                 (Order Load repeated per user)
      #
      #  8. Scope tracking              code.activerecord.scope: "recent_completed"
      #                                 code.activerecord.scope: "high_value"
      #
      #  9. Slow query flag             db.slow: true
      #                                 (any query exceeding slow_query_threshold_ms)
      #
      # 10. Span rename                 span.name: "Order.completed" / "User.active"
      #                                 (via span_name_formatter)
      # ─────────────────────────────────────────────────────────────────────
      def otel_v8_features
        results = {}

        # ── 1 & 2. Frameable: OrderAnalyticsService ──────────────────────────
        # DB spans inside revenue_summary get:
        #   code.namespace: "OrderAnalyticsService", code.function: "revenue_summary"
        svc = OrderAnalyticsService.new
        results[:revenue]      = svc.revenue_summary
        results[:high_value]   = svc.high_value_orders(threshold: 100)

        # ── 1 & 3. Frameable: UserRepository ─────────────────────────────────
        # DB spans inside find_active_users get:
        #   code.namespace: "UserRepository", code.function: "find_active_users"
        repo = UserRepository.new
        results[:active_count] = repo.find_active_users.size
        results[:plan_counts]  = repo.count_by_plan
        results[:admins]       = repo.admins_with_orders

        # ── 4. SQL-named span: UPDATE via update_all ──────────────────────────
        # update_all fires sql.active_record with name="SQL" and the raw SQL.
        # parse_sql_context resolves "transactions" table → Transaction model.
        # Span gets: code.activerecord.model: "Transaction", method: "Update"
        Transaction.where(status: 'processing').limit(1)
                   .update_all(status: 'processing')   # no-op UPDATE, safe

        # ── 5. SQL-named span: raw SELECT via connection.execute ──────────────
        # connection.execute fires name="SQL" with literal SQL.
        # parse_sql_context resolves "users" table → User model.
        # Span gets: code.activerecord.model: "User", method: "Select"
        ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM users WHERE role = 'admin'"
        )

        # ── 6. db.async — async queries ───────────────────────────────────────
        # Rails 7.1+ async_count fires with payload[:async] = true.
        # Span gets: db.async: true
        async_users  = User.async_count
        async_orders = Order.async_count
        results[:async_user_count]  = async_users.value
        results[:async_order_count] = async_orders.value

        # ── 7. N+1 detection — db.query_count ────────────────────────────────
        # Load a few users, then query each one's order count individually.
        # The repeated "Order Count" query increments query_key counter.
        # Spans get: db.query_count: 2, 3, 4, 5
        users_sample = User.limit(5).to_a
        results[:order_counts_per_user] = users_sample.map do |u|
          { user: u.name, orders: u.orders.count }
        end

        # ── 8. Scope tracking ─────────────────────────────────────────────────
        # Scopes captured via RelationScopeCapture on scope macro methods.
        # Span gets: code.activerecord.scope: "recent_completed"
        results[:scoped_transactions] = Transaction.recent_completed.map(&:transaction_id)
        results[:scoped_orders]       = Order.completed.high_value.count

        # ── 9. Slow query simulation ──────────────────────────────────────────
        # SLEEP(0.2) exceeds the 100ms slow_query_threshold_ms.
        # Span gets: db.slow: true
        ActiveRecord::Base.connection.execute("SELECT SLEEP(0.2)")

        render json: { ok: true, results: results }
      end

      # GET /api/v1/demo/redis
      #
      # Exercises rails-otel-context Redis adapter enrichment (v0.8.5+).
      # Every Redis span will carry code.namespace / code.function / code.filepath / code.lineno
      # pointing back to this controller method.
      #
      # What to verify in your OTel backend after hitting this endpoint:
      #
      #  FEATURE                    ATTRIBUTE TO CHECK
      #  ───────────────────────────────────────────────────────────────
      #  Redis SET / GET / DEL      code.namespace: "Api::V1::DemoController"
      #                             code.function:  "redis_demo"
      #                             code.filepath:  "app/controllers/api/v1/demo_controller.rb"
      #                             code.lineno:    <line number>
      #  Pipelined MSET             same code.* attrs on all commands in pipeline
      # ───────────────────────────────────────────────────────────────
      def redis_demo
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
        results = {}

        # Simple SET / GET — one span each; both carry code.* from this method
        redis.set('rails_otel_context:demo:greeting', 'hello from rails-otel-context v0.8.5')
        results[:greeting] = redis.get('rails_otel_context:demo:greeting')

        # Increment counter — demonstrates numeric value path
        redis.set('rails_otel_context:demo:counter', 0)
        redis.incr('rails_otel_context:demo:counter')
        redis.incr('rails_otel_context:demo:counter')
        results[:counter] = redis.get('rails_otel_context:demo:counter').to_i

        # Pipelined write — single pipeline span carrying code.* attrs
        redis.pipelined do |pipe|
          pipe.set('rails_otel_context:demo:pipeline:a', 'alpha')
          pipe.set('rails_otel_context:demo:pipeline:b', 'beta')
          pipe.set('rails_otel_context:demo:pipeline:c', 'gamma')
        end
        results[:pipeline_keys] = redis.keys('rails_otel_context:demo:pipeline:*').sort

        # List operations
        redis.del('rails_otel_context:demo:list')
        redis.rpush('rails_otel_context:demo:list', %w[x y z])
        results[:list] = redis.lrange('rails_otel_context:demo:list', 0, -1)

        # Cleanup
        redis.del(
          'rails_otel_context:demo:greeting',
          'rails_otel_context:demo:counter',
          'rails_otel_context:demo:pipeline:a',
          'rails_otel_context:demo:pipeline:b',
          'rails_otel_context:demo:pipeline:c',
          'rails_otel_context:demo:list'
        )

        render json: { ok: true, results: results }
      end
    end
  end
end
