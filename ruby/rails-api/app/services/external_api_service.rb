# Service for external HTTP calls - creates child spans in traces
class ExternalApiService
  ENDPOINTS = {
    fraud_check: 'https://httpbin.org/post',
    payment_gateway: 'https://httpbin.org/post',
    notification: 'https://httpbin.org/post',
    user_verification: 'https://httpbin.org/get',
    exchange_rate: 'https://httpbin.org/get'
  }.freeze

  class << self
    def fraud_check(transaction_id:, amount:, user_id:)
      call_external(:fraud_check, {
        transaction_id: transaction_id,
        amount: amount,
        user_id: user_id,
        check_type: 'transaction'
      })
    end

    def process_with_gateway(transaction_id:, amount:, currency:, method:)
      call_external(:payment_gateway, {
        transaction_id: transaction_id,
        amount: amount,
        currency: currency,
        payment_method: method
      })
    end

    def send_notification(user_id:, type:, message:)
      call_external(:notification, {
        user_id: user_id,
        notification_type: type,
        message: message
      })
    end

    def verify_user(user_id:)
      call_external(:user_verification, { user_id: user_id }, method: :get)
    end

    def get_exchange_rate(from:, to:)
      call_external(:exchange_rate, { from: from, to: to }, method: :get)
    end

    private

    def call_external(service, params, method: :post)
      url = ENDPOINTS[service]
      service_name = service.to_s.gsub('_', '-')

      tracer.in_span("external.#{service_name}",
        kind: :client,
        attributes: {
          "http.method" => method.to_s.upcase,
          "http.url" => url,
          "external.service" => service_name
        }
      ) do |span|
        begin
          # Simulate network latency
          sleep(rand(50..200) / 1000.0)

          response = if method == :get
            connection.get(url, params)
          else
            connection.post(url, params.to_json, 'Content-Type' => 'application/json')
          end

          span.set_attribute("http.status_code", response.status)
          span.set_attribute("external.success", response.success?)

          if response.success?
            { success: true, status: response.status, data: safe_parse(response.body) }
          else
            span.status = OpenTelemetry::Trace::Status.error("HTTP #{response.status}")
            { success: false, status: response.status, error: response.body }
          end
        rescue Faraday::Error => e
          span.set_attribute("external.error", e.class.name)
          span.set_attribute("external.error_message", e.message)
          span.status = OpenTelemetry::Trace::Status.error(e.message)
          { success: false, error: e.message }
        rescue StandardError => e
          span.set_attribute("external.error", e.class.name)
          { success: false, error: e.message }
        end
      end
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.timeout = 5
        f.options.open_timeout = 2
        f.adapter Faraday.default_adapter
      end
    end

    def safe_parse(body)
      JSON.parse(body) rescue body
    end

    def tracer
      OpenTelemetry.tracer_provider.tracer('external-api-service')
    end
  end
end
