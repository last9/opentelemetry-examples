# frozen_string_literal: true

RailsOtelContext.configure do |config|
  # Flag any query slower than 100ms with db.slow: true
  config.slow_query_threshold_ms = 100

  # Rename DB spans: scope > custom method > AR operation
  config.span_name_formatter = lambda { |original_name, ar_context|
    model = ar_context[:model_name]
    return original_name unless model

    scope   = ar_context[:scope_name]
    code_fn = ar_context[:code_function]
    code_ns = ar_context[:code_namespace]
    ar_op   = ar_context[:method_name]

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
end
