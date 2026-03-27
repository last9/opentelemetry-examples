class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy

  validates :order_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending processing shipped completed cancelled] }

  scope :recent, -> { order(created_at: :desc).limit(20) }
  scope :by_status, ->(status) { where(status: status) }
  scope :high_value, -> { where('total > ?', 100) }
  scope :completed, -> { where(status: 'completed') }

  def self.revenue_by_month
    completed
      .group("DATE_FORMAT(created_at, '%Y-%m')")
      .sum(:total)
  end

  def self.average_order_value
    completed.average(:total)
  end

  def calculate_total!
    update!(total: order_items.sum('quantity * unit_price'))
  end
end
