# frozen_string_literal: true

# Second Frameable example — DB spans show code.namespace: "UserRepository"
# with the exact method name (find_active_users, count_by_plan, etc.).
class UserRepository
  include RailsOtelContext::Frameable

  def find_active_users
    with_otel_frame { User.active.to_a }
  end

  def find_top_spenders(limit = 5)
    with_otel_frame { User.top_spenders(limit).to_a }
  end

  def count_by_plan
    with_otel_frame do
      { free: User.by_plan('free').count, pro: User.by_plan('pro').count }
    end
  end

  def admins_with_orders
    # Eager load — produces code.activerecord.scope via includes
    with_otel_frame do
      User.includes(:orders).admins.map do |u|
        { name: u.name, order_count: u.orders.size }
      end
    end
  end
end
