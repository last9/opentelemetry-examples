# frozen_string_literal: true

RailsOtelContext.configure do |config|
  # Trilogy adapter: track all queries for demo
  config.trilogy_slow_query_enabled = true
  config.trilogy_slow_query_threshold_ms = 0.0

  # Rename DB spans: scope > custom method > AR operation
  config.span_name_formatter = lambda { |original_name, ar_context|
    model = ar_context[:model_name]
    return original_name unless model

    scope   = ar_context[:scope_name]      # "recent_completed" (lazy scopes)
    code_fn = ar_context[:code_function]   # "total_revenue" (terminal methods)
    code_ns = ar_context[:code_namespace]  # "Transaction"
    ar_op   = ar_context[:method_name]     # "Load", "Count", "Create"

    method = if scope
               scope
             elsif code_fn && code_ns == model && !code_fn.start_with?('<')
               code_fn
             else
               ar_op
             end

    "#{model}.#{method}"
  }

  # Propagate controller + action to all child spans
  config.request_context_enabled = true

  # Propagate team to ALL spans (DB, HTTP, Redis)
  config.custom_span_attributes = lambda {
    team = CurrentRequest.team
    team ? { 'team' => team } : nil
  }
end
