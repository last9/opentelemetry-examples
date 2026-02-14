class ApplicationController < ActionController::API
  include NamespaceTraceable

  before_action :set_controller_action_trace_attributes

  private

  def set_controller_action_trace_attributes
    span = OpenTelemetry::Trace.current_span
    return unless span.context.valid?

    span.set_attribute("rails.controller", self.class.name)
    span.set_attribute("rails.action", action_name)
  end
end
