module NamespaceTraceable
  extend ActiveSupport::Concern

  included do
    around_action :trace_with_namespace, if: -> { self.class.const_defined?(:SERVICE_NAMESPACE) }
  end

  private

  def trace_with_namespace(&block)
    namespace = self.class::SERVICE_NAMESPACE

    # Store in request-scoped CurrentAttributes (auto-resets between requests)
    CurrentRequest.service_namespace = namespace

    # Set attribute on current span
    current_span.set_attribute("service.namespace", namespace)

    begin
      block.call
    ensure
      # Explicitly clear to prevent any leakage
      CurrentRequest.service_namespace = nil
    end
  end

  def current_span
    OpenTelemetry::Trace.current_span
  end
end
