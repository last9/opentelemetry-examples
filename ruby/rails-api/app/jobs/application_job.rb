# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  around_enqueue :set_job_trace_attributes_on_enqueue
  around_perform :set_job_trace_attributes_on_perform

  private

  def set_job_trace_attributes_on_enqueue
    set_job_trace_attributes
    yield
  end

  def set_job_trace_attributes_on_perform
    set_job_trace_attributes
    yield
  end

  def set_job_trace_attributes
    span = OpenTelemetry::Trace.current_span
    return unless span.context.valid?

    span.set_attribute('job.name', self.class.name)
    span.set_attribute('active_job.name', self.class.name)
    span.set_attribute('active_job.queue_name', queue_name.to_s)
  end
end
