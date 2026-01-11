# Service for database operations - ActiveRecord already creates spans via instrumentation
# This adds custom business-level spans wrapping DB operations
class DatabaseService
  class << self
    def create_transaction(attrs)
      tracer.in_span("db.create_transaction", attributes: {
        "db.operation" => "insert",
        "db.table" => "transactions"
      }) do |span|
        txn = Transaction.create!(attrs)
        span.set_attribute("db.transaction_id", txn.transaction_id)
        span.set_attribute("db.record_id", txn.id)
        txn
      rescue ActiveRecord::RecordInvalid => e
        span.set_attribute("db.error", e.message)
        span.status = OpenTelemetry::Trace::Status.error(e.message)
        nil
      end
    end

    def find_transaction(transaction_id)
      tracer.in_span("db.find_transaction", attributes: {
        "db.operation" => "select",
        "db.table" => "transactions",
        "db.transaction_id" => transaction_id
      }) do |span|
        txn = Transaction.find_by(transaction_id: transaction_id)
        span.set_attribute("db.found", !txn.nil?)
        txn
      end
    end

    def update_transaction_status(transaction_id, status)
      tracer.in_span("db.update_transaction_status", attributes: {
        "db.operation" => "update",
        "db.table" => "transactions",
        "db.new_status" => status
      }) do |span|
        txn = Transaction.find_by(transaction_id: transaction_id)
        if txn
          txn.update!(status: status)
          span.set_attribute("db.updated", true)
          txn
        else
          span.set_attribute("db.updated", false)
          span.set_attribute("db.error", "Transaction not found")
          nil
        end
      end
    end

    def recent_transactions(limit: 10)
      tracer.in_span("db.recent_transactions", attributes: {
        "db.operation" => "select",
        "db.table" => "transactions",
        "db.limit" => limit
      }) do |span|
        transactions = Transaction.recent.limit(limit)
        span.set_attribute("db.count", transactions.size)
        transactions
      end
    end

    def transactions_by_user(user_id, limit: 10)
      tracer.in_span("db.transactions_by_user", attributes: {
        "db.operation" => "select",
        "db.table" => "transactions",
        "db.user_id" => user_id
      }) do |span|
        transactions = Transaction.by_user(user_id).limit(limit)
        span.set_attribute("db.count", transactions.size)
        transactions
      end
    end

    def transaction_stats
      tracer.in_span("db.transaction_stats", attributes: {
        "db.operation" => "aggregate",
        "db.table" => "transactions"
      }) do |span|
        stats = {
          total: Transaction.count,
          completed: Transaction.by_status('completed').count,
          pending: Transaction.by_status('pending').count,
          failed: Transaction.by_status('failed').count,
          total_amount: Transaction.sum(:amount)
        }
        span.set_attribute("db.total_records", stats[:total])
        stats
      end
    end

    private

    def tracer
      OpenTelemetry.tracer_provider.tracer('database-service')
    end
  end
end
