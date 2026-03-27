class User < ApplicationRecord
  has_many :orders, dependent: :destroy
  has_many :transactions, primary_key: :email, foreign_key: :user_id

  validates :email, presence: true, uniqueness: true

  scope :active, -> { where('last_login_at > ?', 30.days.ago) }
  scope :by_plan, ->(plan) { where(plan: plan) }
  scope :admins, -> { where(role: 'admin') }

  def self.top_spenders(limit = 10)
    joins(:orders)
      .where(orders: { status: 'completed' })
      .group(:id)
      .order('SUM(orders.total) DESC')
      .limit(limit)
      .select('users.*, SUM(orders.total) as total_spent')
  end

  def self.signup_stats
    {
      total: count,
      this_month: where('created_at > ?', 1.month.ago).count,
      active: active.count
    }
  end
end
