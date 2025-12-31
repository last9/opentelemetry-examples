"""
Cloud Run Job with OpenTelemetry Instrumentation
Sends traces, logs, and metrics to Last9

This example demonstrates:
- Task-aware batch processing with OTEL tracing
- Structured JSON logging with trace correlation
- Graceful telemetry flush before job completion
- Error handling with span recording

Environment Variables (set by Cloud Run):
- CLOUD_RUN_TASK_INDEX: Index of this task (0-based)
- CLOUD_RUN_TASK_ATTEMPT: Retry attempt number (0-based)
- CLOUD_RUN_TASK_COUNT: Total number of tasks

User-defined Environment Variables:
- SLEEP_MS: Simulated work duration in milliseconds
- FAIL_RATE: Probability of random failure (0.0-1.0)
"""
import os
import sys
import json
import random
import time
import atexit
from datetime import datetime

from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes


def get_cloud_run_job_resource():
    """Create resource with Cloud Run Job-specific attributes."""
    service_name = os.environ.get("OTEL_SERVICE_NAME", "cloud-run-job")
    job_name = os.environ.get("CLOUD_RUN_JOB", service_name)

    return Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_VERSION: os.environ.get("SERVICE_VERSION", "1.0.0"),
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: os.environ.get("DEPLOYMENT_ENVIRONMENT", "production"),
        # Cloud provider attributes
        "cloud.provider": "gcp",
        "cloud.platform": "gcp_cloud_run_job",
        "cloud.region": os.environ.get("CLOUD_RUN_REGION", os.environ.get("GOOGLE_CLOUD_REGION", "unknown")),
        "cloud.account.id": os.environ.get("GOOGLE_CLOUD_PROJECT", "unknown"),
        # Cloud Run Job specific attributes
        "faas.name": job_name,
        "faas.version": os.environ.get("CLOUD_RUN_EXECUTION", "unknown"),
        "faas.instance": f"task-{os.environ.get('CLOUD_RUN_TASK_INDEX', '0')}",
        # Job execution context
        "cloud_run.job.name": job_name,
        "cloud_run.job.execution": os.environ.get("CLOUD_RUN_EXECUTION", "unknown"),
        "cloud_run.job.task_index": os.environ.get("CLOUD_RUN_TASK_INDEX", "0"),
        "cloud_run.job.task_count": os.environ.get("CLOUD_RUN_TASK_COUNT", "1"),
    })


def parse_otlp_headers():
    """Parse OTLP headers from environment variable."""
    headers_str = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    headers = {}
    if headers_str:
        for pair in headers_str.split(","):
            if "=" in pair:
                key, value = pair.split("=", 1)
                headers[key.strip()] = value.strip()
    return headers


# Global telemetry providers
trace_provider = None
meter_provider = None


def initialize_telemetry():
    """Initialize OpenTelemetry tracing and metrics."""
    global trace_provider, meter_provider

    resource = get_cloud_run_job_resource()
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "https://your-otlp-endpoint")
    headers = parse_otlp_headers()

    # Initialize Tracing
    trace_exporter = OTLPSpanExporter(
        endpoint=f"{endpoint}/v1/traces",
        headers=headers,
    )

    trace_provider = TracerProvider(resource=resource)
    trace_provider.add_span_processor(
        BatchSpanProcessor(
            trace_exporter,
            max_export_batch_size=512,
            schedule_delay_millis=1000,  # Faster flush for jobs
        )
    )
    trace.set_tracer_provider(trace_provider)

    # Initialize Metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=f"{endpoint}/v1/metrics",
        headers=headers,
    )

    metric_reader = PeriodicExportingMetricReader(
        metric_exporter,
        export_interval_millis=10000,  # Export every 10 seconds for jobs
    )

    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader],
    )
    metrics.set_meter_provider(meter_provider)

    return trace.get_tracer(__name__), metrics.get_meter(__name__)


def shutdown_telemetry():
    """Flush and shutdown telemetry providers."""
    global trace_provider, meter_provider

    structured_log("INFO", "Flushing telemetry before exit")

    try:
        if trace_provider:
            trace_provider.force_flush(timeout_millis=10000)
            trace_provider.shutdown()
        if meter_provider:
            meter_provider.force_flush(timeout_millis=10000)
            meter_provider.shutdown()
        structured_log("INFO", "Telemetry shutdown complete")
    except Exception as e:
        print(f"Error during telemetry shutdown: {e}", file=sys.stderr)


def structured_log(level, message, extra=None):
    """Output structured JSON log with trace correlation."""
    span = trace.get_current_span()
    span_context = span.get_span_context() if span else None

    log_entry = {
        "severity": level,
        "message": message,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "job": os.environ.get("CLOUD_RUN_JOB", "unknown"),
        "execution": os.environ.get("CLOUD_RUN_EXECUTION", "unknown"),
        "task_index": os.environ.get("CLOUD_RUN_TASK_INDEX", "0"),
        "task_attempt": os.environ.get("CLOUD_RUN_TASK_ATTEMPT", "0"),
    }

    # Add trace correlation
    if span_context and span_context.is_valid:
        project_id = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
        if project_id:
            log_entry["logging.googleapis.com/trace"] = \
                f"projects/{project_id}/traces/{format(span_context.trace_id, '032x')}"
            log_entry["logging.googleapis.com/spanId"] = format(span_context.span_id, '016x')

    if extra:
        log_entry.update(extra)

    print(json.dumps(log_entry))


def process_task(tracer, meter, task_index, task_count, sleep_ms, fail_rate):
    """
    Process a single task with OpenTelemetry instrumentation.

    In a real application, this would process a partition of data
    based on the task_index (e.g., task_index / task_count of total records).
    """
    # Create task counter metric
    task_counter = meter.create_counter(
        name="job_tasks_total",
        description="Total number of job tasks processed",
        unit="1",
    )

    task_duration = meter.create_histogram(
        name="job_task_duration_seconds",
        description="Job task duration in seconds",
        unit="s",
    )

    with tracer.start_as_current_span("process_task") as span:
        start_time = time.time()

        # Set task context attributes
        span.set_attribute("task.index", task_index)
        span.set_attribute("task.count", task_count)
        span.set_attribute("task.attempt", int(os.environ.get("CLOUD_RUN_TASK_ATTEMPT", "0")))

        structured_log("INFO", f"Starting task {task_index} of {task_count}", {
            "sleep_ms": sleep_ms,
            "fail_rate": fail_rate,
        })

        try:
            # Simulate data processing work
            with tracer.start_as_current_span("simulate_work") as work_span:
                work_span.set_attribute("work.duration_ms", sleep_ms)

                # In a real job, you would:
                # 1. Calculate data partition based on task_index/task_count
                # 2. Fetch data for this partition
                # 3. Process the data
                # 4. Store results

                time.sleep(sleep_ms / 1000.0)
                work_span.add_event("Work simulation completed")

            # Simulate random failures for testing retry behavior
            if random.random() < fail_rate:
                raise RuntimeError(f"Simulated random failure (fail_rate={fail_rate})")

            # Record success
            span.set_attribute("task.status", "success")
            span.add_event("Task completed successfully")

            task_counter.add(1, attributes={
                "task.status": "success",
                "task.index": str(task_index),
            })

            duration = time.time() - start_time
            task_duration.record(duration, attributes={
                "task.status": "success",
            })

            structured_log("INFO", f"Task {task_index} completed successfully", {
                "duration_seconds": round(duration, 3),
            })

            return True

        except Exception as e:
            # Record failure
            span.set_attribute("task.status", "failed")
            span.set_attribute("error", True)
            span.record_exception(e)

            task_counter.add(1, attributes={
                "task.status": "failed",
                "task.index": str(task_index),
            })

            duration = time.time() - start_time
            task_duration.record(duration, attributes={
                "task.status": "failed",
            })

            structured_log("ERROR", f"Task {task_index} failed: {e}", {
                "duration_seconds": round(duration, 3),
                "error": str(e),
            })

            raise


def main():
    """Main entry point for Cloud Run Job."""
    # Initialize telemetry
    tracer, meter = initialize_telemetry()

    # Register shutdown handler
    atexit.register(shutdown_telemetry)

    # Get Cloud Run Job environment variables
    task_index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", "0"))
    task_count = int(os.environ.get("CLOUD_RUN_TASK_COUNT", "1"))
    task_attempt = int(os.environ.get("CLOUD_RUN_TASK_ATTEMPT", "0"))

    # Get user-defined configuration
    sleep_ms = int(os.environ.get("SLEEP_MS", "1000"))
    fail_rate = float(os.environ.get("FAIL_RATE", "0.0"))

    # Create root span for the entire job execution
    with tracer.start_as_current_span("cloud_run_job_execution") as root_span:
        root_span.set_attribute("job.name", os.environ.get("CLOUD_RUN_JOB", "unknown"))
        root_span.set_attribute("job.execution", os.environ.get("CLOUD_RUN_EXECUTION", "unknown"))
        root_span.set_attribute("job.task_index", task_index)
        root_span.set_attribute("job.task_count", task_count)
        root_span.set_attribute("job.task_attempt", task_attempt)

        structured_log("INFO", "Job execution started", {
            "task_index": task_index,
            "task_count": task_count,
            "task_attempt": task_attempt,
        })

        try:
            process_task(tracer, meter, task_index, task_count, sleep_ms, fail_rate)
            root_span.set_attribute("job.status", "success")
            structured_log("INFO", "Job execution completed successfully")

        except Exception as e:
            root_span.set_attribute("job.status", "failed")
            root_span.set_attribute("error", True)
            structured_log("ERROR", f"Job execution failed: {e}")

            # Ensure telemetry is flushed before exit
            shutdown_telemetry()
            sys.exit(1)

    # Ensure telemetry is flushed before normal exit
    shutdown_telemetry()
    sys.exit(0)


if __name__ == "__main__":
    main()
