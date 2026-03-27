module NamespaceTraceable
  extend ActiveSupport::Concern

  included do
    around_action :trace_with_namespace, if: -> { self.class.const_defined?(:SERVICE_NAMESPACE) }
  end

  private

  def trace_with_namespace(&block)
    # Store in request-scoped CurrentAttributes — the rails-otel-context gem's
    # custom_span_attributes lambda reads this and propagates to ALL spans.
    CurrentRequest.service_namespace = self.class::SERVICE_NAMESPACE
    block.call
  end
end
