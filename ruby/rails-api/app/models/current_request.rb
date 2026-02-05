# Request-scoped storage for OpenTelemetry attributes
# Automatically resets between requests - prevents namespace leakage
class CurrentRequest < ActiveSupport::CurrentAttributes
  attribute :service_namespace
end
