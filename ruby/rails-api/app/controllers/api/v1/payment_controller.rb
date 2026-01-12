module Api
  module V1
    class PaymentController < ApplicationController
      SERVICE_NAMESPACE = "payment".freeze

      # GET /api/v1/payment/status
      def status
        # Check cache for gateway status
        cached_status = CacheService.get("gateway:status")

        if cached_status
          current_span.set_attribute("payment.cache_hit", true)
          render json: JSON.parse(cached_status)
          return
        end

        # Simulate checking payment gateway
        simulate_work(50..150)

        status_data = {
          status: "operational",
          gateway: "stripe",
          latency_ms: rand(10..50),
          timestamp: Time.now.iso8601
        }

        # Cache the status
        CacheService.set("gateway:status", status_data.to_json, ex: 60)

        current_span.set_attribute("payment.gateway", "stripe")
        current_span.set_attribute("payment.gateway_status", "healthy")
        current_span.set_attribute("payment.cache_hit", false)

        render json: status_data
      end

      # POST /api/v1/payment/process
      def process_payment
        amount = params[:amount]&.to_f || rand(10.0..500.0).round(2)
        currency = params[:currency] || "USD"
        payment_method = params[:method] || "card"
        user_id = params[:user_id] || "usr_#{SecureRandom.hex(8)}"

        transaction_id = "txn_#{SecureRandom.hex(12)}"

        current_span.set_attribute("payment.amount", amount)
        current_span.set_attribute("payment.currency", currency)
        current_span.set_attribute("payment.method", payment_method)
        current_span.set_attribute("payment.transaction_id", transaction_id)

        # 1. Check fraud (external API call)
        fraud_result = ExternalApiService.fraud_check(
          transaction_id: transaction_id,
          amount: amount,
          user_id: user_id
        )
        current_span.set_attribute("payment.fraud_check_passed", fraud_result[:success])

        # 2. Create transaction in database
        txn = DatabaseService.create_transaction(
          transaction_id: transaction_id,
          amount: amount,
          currency: currency,
          status: 'processing',
          payment_method: payment_method,
          user_id: user_id
        )

        # 3. Process with payment gateway (external API call)
        gateway_result = ExternalApiService.process_with_gateway(
          transaction_id: transaction_id,
          amount: amount,
          currency: currency,
          method: payment_method
        )

        # 4. Update transaction status
        final_status = (rand < 0.1) ? 'failed' : 'completed'
        DatabaseService.update_transaction_status(transaction_id, final_status)

        # 5. Cache the result
        CacheService.set("txn:#{transaction_id}", { status: final_status, amount: amount }.to_json, ex: 300)

        # 6. Increment counter
        CacheService.increment("payments:count:#{Date.today}")

        current_span.set_attribute("payment.status", final_status)

        if final_status == 'failed'
          current_span.set_attribute("payment.error_code", "insufficient_funds")
          render json: {
            success: false,
            error: "insufficient_funds",
            transaction_id: transaction_id
          }, status: :payment_required
        else
          # Send notification (external API call)
          ExternalApiService.send_notification(
            user_id: user_id,
            type: 'payment_success',
            message: "Payment of #{amount} #{currency} completed"
          )

          render json: {
            success: true,
            transaction_id: transaction_id,
            amount: amount,
            currency: currency
          }
        end
      end

      # POST /api/v1/payment/refund
      def refund
        transaction_id = params[:transaction_id] || "txn_#{SecureRandom.hex(12)}"
        amount = params[:amount]&.to_f || rand(10.0..100.0).round(2)

        current_span.set_attribute("payment.original_transaction_id", transaction_id)
        current_span.set_attribute("payment.refund_amount", amount)

        # 1. Find original transaction
        original_txn = DatabaseService.find_transaction(transaction_id)

        # 2. Check cache for transaction details
        cached_txn = CacheService.get("txn:#{transaction_id}")
        current_span.set_attribute("payment.cache_hit", !cached_txn.nil?)

        # 3. Create refund transaction
        refund_id = "ref_#{SecureRandom.hex(8)}"
        DatabaseService.create_transaction(
          transaction_id: refund_id,
          amount: -amount,
          currency: original_txn&.currency || 'USD',
          status: 'completed',
          payment_method: 'refund',
          user_id: original_txn&.user_id,
          metadata: { original_transaction: transaction_id }.to_json
        )

        # 4. Process refund with gateway
        ExternalApiService.process_with_gateway(
          transaction_id: refund_id,
          amount: -amount,
          currency: 'USD',
          method: 'refund'
        )

        # 5. Update original transaction status
        DatabaseService.update_transaction_status(transaction_id, 'refunded') if original_txn

        # 6. Invalidate cache
        CacheService.delete("txn:#{transaction_id}")

        current_span.set_attribute("payment.refund_id", refund_id)
        current_span.set_attribute("payment.refund_status", "completed")

        render json: {
          success: true,
          refund_id: refund_id,
          original_transaction_id: transaction_id,
          amount: amount
        }
      end

      # GET /api/v1/payment/transactions
      def transactions
        limit = (params[:limit] || 10).to_i
        user_id = params[:user_id]

        current_span.set_attribute("payment.query_limit", limit)

        # 1. Try cache first
        cache_key = user_id ? "txns:user:#{user_id}" : "txns:recent"
        cached = CacheService.get(cache_key)

        if cached
          current_span.set_attribute("payment.cache_hit", true)
          render json: JSON.parse(cached)
          return
        end

        # 2. Query database
        transactions = if user_id
          DatabaseService.transactions_by_user(user_id, limit: limit)
        else
          DatabaseService.recent_transactions(limit: limit)
        end

        # 3. Get stats
        stats = DatabaseService.transaction_stats

        result = {
          transactions: transactions.map { |t|
            {
              id: t.transaction_id,
              amount: t.amount.to_f,
              currency: t.currency,
              status: t.status,
              created_at: t.created_at.iso8601
            }
          },
          total: transactions.size,
          stats: stats
        }

        # 4. Cache the result
        CacheService.set(cache_key, result.to_json, ex: 60)

        current_span.set_attribute("payment.transactions_returned", transactions.size)
        current_span.set_attribute("payment.cache_hit", false)

        render json: result
      end

      private

      def current_span
        OpenTelemetry::Trace.current_span
      end

      def simulate_work(range_ms)
        sleep(rand(range_ms) / 1000.0)
      end
    end
  end
end
