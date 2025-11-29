class TestController < ApplicationController
  # API controller - no CSRF or database required

  # Simple health check endpoint
  def health
    render json: { status: 'ok', service: 'ruby-rails-api', timestamp: Time.now }
  end

  # Endpoint with database query (if database is configured)
  def users
    # Simulate database query timing
    sleep(0.1) # Simulates DB latency

    users = [
      { id: 1, name: 'Alice', email: 'alice@example.com' },
      { id: 2, name: 'Bob', email: 'bob@example.com' },
      { id: 3, name: 'Charlie', email: 'charlie@example.com' }
    ]

    render json: { users: users, count: users.length }
  end

  # Endpoint with custom span
  def calculate
    result = 0

    # Create a custom span for calculation
    tracer = OpenTelemetry.tracer_provider.tracer('test-controller')
    tracer.in_span('complex_calculation') do |span|
      span.set_attribute('calculation.type', 'fibonacci')
      span.set_attribute('calculation.input', params[:n].to_i)

      result = fibonacci(params[:n].to_i || 10)

      span.set_attribute('calculation.result', result)
    end

    render json: { input: params[:n], result: result }
  end

  # Endpoint that simulates an error
  def error
    # This will generate an error trace
    raise StandardError, "Simulated error for testing traces"
  rescue => e
    render json: { error: e.message }, status: 500
  end

  # Endpoint with nested spans
  def process_order
    order_id = params[:order_id] || SecureRandom.uuid

    tracer = OpenTelemetry.tracer_provider.tracer('test-controller')

    tracer.in_span('process_order', attributes: { 'order.id' => order_id }) do |parent_span|
      # Validate order
      tracer.in_span('validate_order') do |span|
        span.set_attribute('validation.status', 'success')
        sleep(0.05)
      end

      # Calculate pricing
      tracer.in_span('calculate_pricing') do |span|
        price = rand(100..1000)
        span.set_attribute('order.price', price)
        sleep(0.1)
      end

      # Process payment
      tracer.in_span('process_payment') do |span|
        span.set_attribute('payment.method', 'credit_card')
        span.set_attribute('payment.status', 'success')
        sleep(0.15)
      end
    end

    render json: { order_id: order_id, status: 'processed', timestamp: Time.now }
  end

  # Endpoint with external HTTP call simulation
  def external_api
    tracer = OpenTelemetry.tracer_provider.tracer('test-controller')

    tracer.in_span('external_api_call') do |span|
      span.set_attribute('http.method', 'GET')
      span.set_attribute('http.url', 'https://api.example.com/data')
      span.set_attribute('http.status_code', 200)

      # Simulate API call latency
      sleep(0.3)
    end

    render json: { data: 'External API response', cached: false }
  end

  private

  def fibonacci(n)
    return n if n <= 1
    fibonacci(n - 1) + fibonacci(n - 2)
  end
end