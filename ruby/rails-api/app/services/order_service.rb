# app/services/order_service.rb
class OrderService
  def self.create_from_checkout(user:, cart:, checkout:, payment_id:)
    # Start a transaction to ensure data consistency
    ActiveRecord::Base.transaction do
      # Create the order
      order = Order.create!(
        user: user,
        total_amount: cart.total_amount,
        shipping_address_id: checkout.shipping_address_id,
        shipping_method: checkout.shipping_method,
        special_instructions: checkout.special_instructions,
        payment_id: payment_id,
        status: "pending"
      )
      
      # Add order items from cart
      cart.items.each do |cart_item|
        OrderItem.create!(
          order: order,
          product_id: cart_item.product_id,
          quantity: cart_item.quantity,
          unit_price: cart_item.product.price,
          total_price: cart_item.total_price
        )
      end
      
      order
    end
  end
end

