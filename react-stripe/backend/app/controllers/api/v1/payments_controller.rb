module Api
  module V1
    class PaymentsController < ApplicationController
      # GET /api/v1/health
      def health
        tracer.in_span('stripe.payments.health_check',
          attributes: { 'health.status' => 'ok' }) do
          render json: { status: 'ok', service: 'stripe-payments-api' }
        end
      end

      # POST /api/v1/payment_intents
      #
      # Creates a Stripe PaymentIntent and returns the client_secret to the
      # React frontend. The frontend uses this to mount the PaymentElement and
      # confirm the payment without ever touching raw card data.
      def create
        amount   = params.require(:amount).to_i
        currency = params.fetch(:currency, 'usd')

        tracer.in_span(
          'stripe.payment_intent.create',
          attributes: {
            'payment.amount'   => amount,
            'payment.currency' => currency,
            'payment.gateway'  => 'stripe',
          }
        ) do |span|
          intent = Stripe::PaymentIntent.create(
            amount:                   amount,
            currency:                 currency,
            automatic_payment_methods: { enabled: true },
          )

          span.set_attribute('payment.intent_id', intent.id)
          span.set_attribute('payment.status',    intent.status)

          render json: { client_secret: intent.client_secret }
        end

      rescue Stripe::InvalidRequestError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Stripe::StripeError => e
        render json: { error: e.message }, status: :service_unavailable
      end

      # POST /api/v1/webhooks
      #
      # Receives Stripe webhook events. Each event type gets its own span so
      # you can measure webhook processing latency per event type, and alert on
      # payment_intent.payment_failed spikes in Last9.
      #
      # To test locally:  stripe listen --forward-to localhost:3001/api/v1/webhooks
      def webhook
        payload    = request.body.read
        sig_header = request.env['HTTP_STRIPE_SIGNATURE']

        event = Stripe::Webhook.construct_event(
          payload,
          sig_header,
          ENV.fetch('STRIPE_WEBHOOK_SECRET')
        )

        tracer.in_span(
          'stripe.webhook.process',
          attributes: {
            'stripe.event_type' => event['type'],
            'stripe.event_id'   => event['id'],
          }
        ) do |span|
          handle_event(event, span)
        end

        render json: { received: true }

      rescue Stripe::SignatureVerificationError
        render json: { error: 'Invalid signature' }, status: :bad_request
      rescue JSON::ParserError
        render json: { error: 'Invalid payload' }, status: :bad_request
      rescue KeyError
        render json: { error: 'STRIPE_WEBHOOK_SECRET not set' }, status: :internal_server_error
      end

      private

      def tracer
        @tracer ||= OpenTelemetry.tracer_provider.tracer('stripe-payments', '1.0.0')
      end

      def otel_logger
        @otel_logger ||= OpenTelemetry.logger_provider.logger(name: 'stripe-payments', version: '1.0.0')
      end

      # Lazily resolve severity numbers so OpenTelemetry::Logs isn't referenced
      # at class load time (before the OTel initializer has run).
      def sev(level)
        OpenTelemetry::Logs::SeverityNumber.const_get(:"SEVERITY_NUMBER_#{level}")
      end

      def emit_log(severity:, severity_text:, body:, attributes: {})
        otel_logger.on_emit(
          timestamp:       Time.now,
          severity_number: severity,
          severity_text:   severity_text,
          body:            body,
          attributes:      attributes
        )
      end

      def handle_event(event, span)
        case event['type']
        when 'payment_intent.succeeded'
          pi = event['data']['object']
          span.set_attribute('payment.intent_id', pi['id'])
          span.set_attribute('payment.amount',    pi['amount'])
          span.set_attribute('payment.currency',  pi['currency'])
          span.set_attribute('payment.status',    'succeeded')
          emit_log(severity: sev(:INFO), severity_text: 'INFO', body: 'Payment succeeded',
            attributes: { 'event.name' => 'payment.succeeded', 'payment.intent_id' => pi['id'],
                          'payment.amount' => pi['amount'], 'payment.currency' => pi['currency'] })

        when 'payment_intent.payment_failed'
          pi    = event['data']['object']
          error = pi['last_payment_error'] || {}
          span.set_attribute('payment.intent_id',          pi['id'])
          span.set_attribute('payment.error.code',         error['code']         || 'unknown')
          span.set_attribute('payment.error.decline_code', error['decline_code'] || '')
          span.set_attribute('payment.error.type',         error['type']         || 'unknown')
          span.set_status(OpenTelemetry::Trace::Status.error("Payment failed: #{error['message']}"))
          emit_log(severity: sev(:ERROR), severity_text: 'ERROR', body: "Payment failed: #{error['message']}",
            attributes: { 'event.name' => 'payment.failed', 'payment.intent_id' => pi['id'],
                          'payment.error.code' => error['code'] || 'unknown',
                          'payment.error.decline_code' => error['decline_code'] || '' })

        when 'payment_intent.requires_action'
          pi = event['data']['object']
          span.set_attribute('payment.intent_id', pi['id'])
          span.set_attribute('3ds.required',      true)
          emit_log(severity: sev(:WARN), severity_text: 'WARN', body: '3DS authentication required',
            attributes: { 'event.name' => '3ds.required', 'payment.intent_id' => pi['id'] })

        when 'charge.dispute.created'
          dispute = event['data']['object']
          span.set_attribute('dispute.id',     dispute['id'])
          span.set_attribute('dispute.reason', dispute['reason'] || 'unknown')
          span.set_attribute('dispute.amount', dispute['amount'])
          span.set_status(OpenTelemetry::Trace::Status.error("Dispute raised: #{dispute['reason']}"))
          emit_log(severity: sev(:ERROR), severity_text: 'ERROR', body: "Dispute created: #{dispute['reason']}",
            attributes: { 'event.name' => 'dispute.created', 'dispute.id' => dispute['id'],
                          'dispute.reason' => dispute['reason'] || 'unknown' })
        end
      end
    end
  end
end
