class Transaction < ApplicationRecord
  validates :transaction_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :status, inclusion: { in: %w[pending processing completed failed refunded] }

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
end
