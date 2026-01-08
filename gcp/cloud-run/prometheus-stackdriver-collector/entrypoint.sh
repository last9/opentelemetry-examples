#!/bin/sh
set -e

# Entrypoint script to run both Stackdriver Exporter and Prometheus
# This script ensures both services start correctly and handles graceful shutdown

echo "============================================"
echo "GCP Cloud Run Metrics Collector Starting..."
echo "============================================"
echo ""

# Validate required environment variables
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "ERROR: GCP_PROJECT_ID environment variable is required"
  exit 1
fi

if [ -z "$REMOTE_WRITE_URL" ]; then
  echo "ERROR: REMOTE_WRITE_URL environment variable is required"
  exit 1
fi

if [ -z "$LAST9_USERNAME" ]; then
  echo "ERROR: LAST9_USERNAME environment variable is required"
  exit 1
fi

if [ -z "$LAST9_PASSWORD" ]; then
  echo "ERROR: LAST9_PASSWORD environment variable is required"
  exit 1
fi

echo "Configuration:"
echo "  GCP Project: $GCP_PROJECT_ID"
echo "  Remote Write URL: $REMOTE_WRITE_URL"
echo "  Metric Prefixes: run.googleapis.com, cloudtasks.googleapis.com"
echo ""

# Create prometheus.yml with environment variables substituted manually
# (envsubst not available in prometheus base image)
# Updated: 2026-01-07 with 5-minute scrape intervals to reduce GCP API calls
cat > /tmp/prometheus.yml <<EOF
# Prometheus configuration for GCP Cloud Run/Jobs metrics collection
# Optimized for Last9 remote write with proper timeout handling

global:
  scrape_interval: 5m
  scrape_timeout: 4m30s
  evaluation_interval: 5m
  external_labels:
    environment: 'production'
    source: 'gcp-cloud-run-metrics'
    collector: 'prometheus-stackdriver'

scrape_configs:
  - job_name: 'stackdriver'
    scrape_interval: 5m
    scrape_timeout: 4m30s
    static_configs:
      - targets: ['localhost:9255']
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: '(run_googleapis_com_.*|cloudtasks_googleapis_com_.*)'
        action: keep

  - job_name: 'prometheus'
    scrape_interval: 30s
    scrape_timeout: 10s
    static_configs:
      - targets: ['localhost:8080']

  - job_name: 'stackdriver_exporter'
    scrape_interval: 30s
    scrape_timeout: 10s
    static_configs:
      - targets: ['localhost:9255']
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'stackdriver_.*'
        action: keep

remote_write:
  - url: $REMOTE_WRITE_URL
    basic_auth:
      username: $LAST9_USERNAME
      password: $LAST9_PASSWORD
    queue_config:
      max_samples_per_send: 5000
      max_shards: 10
      min_shards: 1
      capacity: 10000
      batch_send_deadline: 10s
      min_backoff: 30ms
      max_backoff: 5s
    remote_timeout: 30s
    write_relabel_configs:
      - target_label: 'forwarded_by'
        replacement: 'prometheus-stackdriver-collector'
EOF

# Start stackdriver_exporter in the background
echo "Starting Stackdriver Exporter on port 9255..."
# Only collect essential Cloud Run and Cloud Tasks metrics to avoid timeouts
stackdriver_exporter \
  --google.project-id="$GCP_PROJECT_ID" \
  --monitoring.metrics-type-prefixes="run.googleapis.com/request_count,run.googleapis.com/request_latencies,run.googleapis.com/container/cpu/utilizations,run.googleapis.com/container/memory/utilizations,run.googleapis.com/container/instance_count,run.googleapis.com/container/billable_instance_time,cloudtasks.googleapis.com/queue/depth,cloudtasks.googleapis.com/task/attempt_count" \
  --web.listen-address=":9255" \
  --web.telemetry-path="/metrics" \
  --log.level=info \
  --monitoring.drop-delegated-projects \
  --monitoring.metrics-interval="5m" \
  --monitoring.metrics-offset="0s" \
  2>&1 | sed 's/^/[stackdriver_exporter] /' &

STACKDRIVER_PID=$!
echo "Stackdriver Exporter started with PID: $STACKDRIVER_PID"

# Wait for stackdriver_exporter to be ready
echo "Waiting for Stackdriver Exporter to be ready..."
MAX_WAIT=30
WAIT_COUNT=0
until wget -q -O /dev/null http://localhost:9255/metrics 2>/dev/null || [ $WAIT_COUNT -eq $MAX_WAIT ]; do
  WAIT_COUNT=$((WAIT_COUNT + 1))
  echo "  Waiting... ($WAIT_COUNT/$MAX_WAIT)"
  sleep 1
done

if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
  echo "ERROR: Stackdriver Exporter failed to start within ${MAX_WAIT}s"
  exit 1
fi

echo "Stackdriver Exporter is ready!"
echo ""

# Start Prometheus in the foreground
echo "Starting Prometheus on port 8080..."
exec prometheus \
  --config.file=/tmp/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.listen-address=:8080 \
  --web.enable-lifecycle \
  --web.enable-admin-api \
  --log.level=info \
  2>&1 | sed 's/^/[prometheus] /'
