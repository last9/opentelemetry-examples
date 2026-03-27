# Request-scoped storage for OpenTelemetry attributes
# Automatically resets between requests - prevents leakage
class CurrentRequest < ActiveSupport::CurrentAttributes
  attribute :team
end
