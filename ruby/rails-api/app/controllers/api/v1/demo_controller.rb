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
    end
  end
end
