# frozen_string_literal: true

# Demonstrates RailsOtelContext::Frameable — every DB span created inside
# with_otel_frame gets code.namespace: "OrderAnalyticsService" and
# code.function: the method name, sourced from the push model (O(1), no stack walk).
class OrderAnalyticsService
  include RailsOtelContext::Frameable

  def revenue_summary
    with_otel_frame do
      {
        total:   Order.completed.sum(:total).to_f,
        count:   Order.completed.count,
        average: Order.average_order_value.to_f.round(2)
      }
    end
  end

  def high_value_orders(threshold: 100)
    with_otel_frame do
      Order.completed.high_value.limit(10).map do |o|
        { order_number: o.order_number, total: o.total.to_f }
      end
    end
  end

  def recalculate_totals(order_ids)
    with_otel_frame do
      Order.where(id: order_ids).find_each(&:calculate_total!)
    end
  end
end
