class OrderItem < ApplicationRecord
  belongs_to :order

  validates :product_name, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than: 0 }

  scope :expensive, -> { where('unit_price > ?', 50) }

  def self.best_sellers(limit = 5)
    group(:product_name)
      .order('SUM(quantity) DESC')
      .limit(limit)
      .pluck(:product_name, 'SUM(quantity) as total_sold')
  end
end
