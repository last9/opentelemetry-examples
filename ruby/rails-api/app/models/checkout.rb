# app/models/checkout.rb
class Checkout
  include ActiveModel::Model
  include ActiveModel::Validations

  attr_accessor :shipping_address_id, :shipping_method, :special_instructions
  
  validates :shipping_address_id, presence: true
  validates :shipping_method, presence: true, inclusion: { in: %w(standard express next_day) }
end

