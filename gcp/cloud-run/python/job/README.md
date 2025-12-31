# Python Cloud Run Job with OpenTelemetry

Run batch processing jobs on Google Cloud Run with full OpenTelemetry instrumentation, sending traces, logs, and metrics to Last9.

## Features

- Task-aware batch processing with distributed tracing
- Structured JSON logging with trace correlation
- Job execution metrics (task count, duration)
- Automatic retry handling with attempt tracking
- Graceful telemetry flush before job completion

## Cloud Run Jobs vs Services

| Feature | Cloud Run Service | Cloud Run Job |
|---------|------------------|---------------|
| Trigger | HTTP requests | Manual/scheduled execution |
| Scaling | Auto-scales on traffic | Parallel tasks (1-10000) |
| Timeout | Up to 60 minutes | Up to 24 hours |
| Use case | Web APIs, webhooks | Batch processing, ETL |

## Environment Variables

### Set by Cloud Run (automatic)

| Variable | Description |
|----------|-------------|
| `CLOUD_RUN_JOB` | Job name |
| `CLOUD_RUN_EXECUTION` | Unique execution ID |
| `CLOUD_RUN_TASK_INDEX` | Index of this task (0-based) |
| `CLOUD_RUN_TASK_COUNT` | Total number of tasks |
| `CLOUD_RUN_TASK_ATTEMPT` | Retry attempt number (0-based) |

### User-defined

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name for telemetry | `cloud-run-job` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint | `YOUR_OTLP_ENDPOINT` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth header | - |
| `SLEEP_MS` | Simulated work duration (ms) | `1000` |
| `FAIL_RATE` | Random failure probability (0.0-1.0) | `0.0` |

## Local Development

### 1. Set up environment

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure credentials

```bash
export OTEL_SERVICE_NAME=my-batch-job
export OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_CREDENTIALS"

# Simulate Cloud Run Job environment
export CLOUD_RUN_JOB=my-batch-job
export CLOUD_RUN_EXECUTION=local-test-001
export CLOUD_RUN_TASK_INDEX=0
export CLOUD_RUN_TASK_COUNT=1
export CLOUD_RUN_TASK_ATTEMPT=0
```

### 3. Run locally

```bash
python main.py
```

## Deploy to Cloud Run

### 1. Create Last9 secret (one-time)

```bash
# IMPORTANT: Include "Authorization=" prefix
echo -n "Authorization=Basic YOUR_BASE64_CREDENTIALS" | \
  gcloud secrets create last9-auth-header --data-file=-
```

### 2. Deploy the job

```bash
# Deploy from source
gcloud run jobs deploy batch-job-demo \
  --source . \
  --region us-central1 \
  --tasks 10 \
  --max-retries 3 \
  --task-timeout 600 \
  --set-env-vars "OTEL_SERVICE_NAME=batch-job-demo" \
  --set-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=YOUR_OTLP_ENDPOINT" \
  --set-env-vars "SLEEP_MS=5000" \
  --set-env-vars "FAIL_RATE=0.1" \
  --set-secrets "OTEL_EXPORTER_OTLP_HEADERS=last9-auth-header:latest"
```

### 3. Execute the job

```bash
# Run the job
gcloud run jobs execute batch-job-demo --region us-central1

# Watch execution status
gcloud run jobs executions list --job batch-job-demo --region us-central1
```

## Scheduling Jobs

Use Cloud Scheduler to run jobs on a schedule:

```bash
# Create a scheduled trigger (daily at 2 AM)
gcloud scheduler jobs create http batch-job-daily \
  --location us-central1 \
  --schedule "0 2 * * *" \
  --uri "https://us-central1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/PROJECT_ID/jobs/batch-job-demo:run" \
  --http-method POST \
  --oauth-service-account-email PROJECT_NUMBER-compute@developer.gserviceaccount.com
```

## Telemetry Details

### Traces

Each job execution creates spans:

```
cloud_run_job_execution (root span)
├── process_task
│   └── simulate_work
```

Span attributes include:
- `job.name`, `job.execution`, `job.task_index`, `job.task_count`
- `task.status` (success/failed)
- `task.attempt` (retry count)

### Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `job_tasks_total` | Counter | Tasks processed by status |
| `job_task_duration_seconds` | Histogram | Task processing duration |

### Logs

Structured JSON with trace correlation:

```json
{
  "severity": "INFO",
  "message": "Task 0 completed successfully",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "job": "batch-job-demo",
  "execution": "batch-job-demo-abc123",
  "task_index": "0",
  "task_attempt": "0",
  "logging.googleapis.com/trace": "projects/my-project/traces/...",
  "duration_seconds": 5.023
}
```

## Real-World Use Cases

### Data Processing Pipeline

```python
def process_task(tracer, meter, task_index, task_count, ...):
    with tracer.start_as_current_span("process_data_partition") as span:
        # Calculate data partition
        total_records = get_total_record_count()
        partition_size = total_records // task_count
        start_offset = task_index * partition_size
        end_offset = start_offset + partition_size

        span.set_attribute("partition.start", start_offset)
        span.set_attribute("partition.end", end_offset)

        # Process records in this partition
        records = fetch_records(start_offset, end_offset)
        for record in records:
            process_record(record)
```

### ETL Job

```python
def process_task(...):
    with tracer.start_as_current_span("etl_pipeline"):
        # Extract
        with tracer.start_as_current_span("extract"):
            data = extract_from_source(task_index, task_count)

        # Transform
        with tracer.start_as_current_span("transform"):
            transformed = transform_data(data)

        # Load
        with tracer.start_as_current_span("load"):
            load_to_destination(transformed)
```

## Files

| File | Description |
|------|-------------|
| `main.py` | Job entry point with OTEL instrumentation |
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container configuration |
| `README.md` | This documentation |

## Troubleshooting

### Traces not appearing after job completion

The job must flush telemetry before exiting. The `shutdown_telemetry()` function handles this with a 10-second timeout. If your job exits too quickly:

1. Ensure `atexit.register(shutdown_telemetry)` is called
2. Call `shutdown_telemetry()` explicitly before `sys.exit()`

### Task failures not being retried

Check `--max-retries` setting when deploying. Default is 0 (no retries).

### Out of memory errors

Cloud Run Jobs default to 512MB. For data-intensive jobs:

```bash
gcloud run jobs update batch-job-demo \
  --memory 2Gi \
  --cpu 2
```
