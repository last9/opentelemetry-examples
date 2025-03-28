# app/controllers/checkout_controller.rb
class CheckoutController < ApplicationController
  before_action :authenticate_user!
  before_action :set_cart, only: [:new, :create, :payment, :confirm, :complete]
  before_action :validate_cart, only: [:new, :create, :payment]
  rescue_from InvalidCheckoutError, with: :handle_invalid_checkout

  # Display checkout form
  def new
    @checkout = Checkout.new
    @shipping_addresses = current_user.shipping_addresses
    @payment_methods = current_user.payment_methods
  end

  # Process initial checkout information
  def create
    @checkout = Checkout.new(checkout_params)
    
    if @checkout.valid?
      # Store checkout data in session
      session[:checkout] = {
        shipping_address_id: @checkout.shipping_address_id,
        shipping_method: @checkout.shipping_method,
        special_instructions: @checkout.special_instructions
      }
      
      redirect_to payment_checkout_path
    else
      @shipping_addresses = current_user.shipping_addresses
      @payment_methods = current_user.payment_methods
      render :new, status: :unprocessable_entity
    end
  end

  # Show payment form
  def payment
    @checkout = Checkout.new(session[:checkout] || {})
    @payment_methods = current_user.payment_methods
  end

  # Process payment and show confirmation page
  def confirm
    @checkout = Checkout.new(session[:checkout] || {})
    
    begin
      payment_result = process_payment(payment_params)
      
      if payment_result[:success]
        session[:payment_id] = payment_result[:payment_id]
        @order = create_order_from_checkout(@checkout, payment_result[:payment_id])
        render :confirm
      else
        flash.now[:alert] = "Payment failed: #{payment_result[:message]}"
        @payment_methods = current_user.payment_methods
        render :payment, status: :unprocessable_entity
      end
    rescue StandardError => e
      logger.error("Payment processing error: #{e.message}")
      flash.now[:alert] = "There was an error processing your payment. Please try again."
      @payment_methods = current_user.payment_methods
      render :payment, status: :unprocessable_entity
    end
  end

  # Complete the order
  def complete
    payment_id = session[:payment_id]
    
    if payment_id.present?
      @order = Order.find_by(payment_id: payment_id)
      
      if @order
        # Clear checkout session data
        session.delete(:checkout)
        session.delete(:payment_id)
        
        # Empty the cart
        @cart.empty!
        
        # Send confirmation email
        OrderMailer.confirmation_email(@order).deliver_later
      else
        raise InvalidCheckoutError.new("Order not found for payment")
      end
    else
      raise InvalidCheckoutError.new("No payment information found")
    end
  rescue StandardError => e
    logger.error("Order completion error: #{e.message}")
    flash[:alert] = "There was an error completing your order. Please contact support."
    redirect_to cart_path
  end

  private

  def set_cart
    @cart = current_user.cart
  end

  def validate_cart
    raise InvalidCheckoutError.new("Your cart is empty") if @cart.items.empty?
    raise InvalidCheckoutError.new("Some items in your cart are no longer available") unless @cart.items_available?
  end

  def checkout_params
    params.require(:checkout).permit(:shipping_address_id, :shipping_method, :special_instructions)
  end

  def payment_params
    params.require(:payment).permit(:payment_method_id, :save_payment_method)
  end

  def process_payment(payment_params)
    payment_service = PaymentService.new(
      user: current_user,
      cart: @cart,
      payment_method_id: payment_params[:payment_method_id]
    )
    
    payment_service.process
  end

  def create_order_from_checkout(checkout, payment_id)
    OrderService.create_from_checkout(
      user: current_user,
      cart: @cart,
      checkout: checkout,
      payment_id: payment_id
    )
  end

  def handle_invalid_checkout(exception)
    flash[:alert] = exception.message
    redirect_to cart_path
  end
end