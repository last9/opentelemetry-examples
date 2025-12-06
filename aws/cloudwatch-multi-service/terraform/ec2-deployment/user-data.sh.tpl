#!/bin/bash
set -e

# User data script for installing and configuring OpenTelemetry Collector
# on Amazon Linux 2023

# Log all output to file for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=========================================="
echo "Starting OTEL Collector Installation"
echo "=========================================="
echo "Timestamp: $(date)"

# Update system packages
echo "Updating system packages..."
dnf update -y

# Install required packages
echo "Installing required packages..."
dnf install -y wget curl jq

# Download and install OpenTelemetry Collector Contrib
echo "Downloading OpenTelemetry Collector Contrib v${otel_version}..."
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${otel_version}/otelcol-contrib_${otel_version}_linux_amd64.rpm

echo "Installing OpenTelemetry Collector..."
rpm -ivh otelcol-contrib_${otel_version}_linux_amd64.rpm

# Create OTEL Collector configuration
echo "Creating OTEL Collector configuration..."
cat > /etc/otelcol-contrib/config.yaml << 'EOF'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

  awscloudwatch:
    region: ${aws_region}
    logs:
      poll_interval: 2m
      groups:
        autodiscover:
          limit: 100
          prefix: ${log_group_prefix}
        named:
          ${log_group_names}

processors:
  batch:
    timeout: 40s
    send_batch_size: 100000
    send_batch_max_size: 100000

  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128

  transform/add_timestamp:
    error_mode: ignore
    log_statements:
      - context: log
        conditions:
          - time_unix_nano == 0
        statements:
          - set(observed_time, Now())
          - set(time_unix_nano, observed_time_unix_nano)

  transform/logs:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          - set(resource.attributes["service.name"], "${service_name}") where resource.attributes["service.name"] == nil
          - set(attributes["source"], "cloudwatch")

  resourcedetection/system:
    detectors: [env, system, ec2]
    timeout: 5s
    override: false

exporters:
  debug:
    verbosity: detailed
    sampling_initial: 5
    sampling_thereafter: 200

  otlp/last9:
    endpoint: "${last9_otlp_endpoint}"
    headers:
      Authorization: "${last9_auth_header}"
    compression: gzip
    timeout: 30s
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 5000

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    logs:
      receivers: [awscloudwatch, otlp]
      processors:
        - memory_limiter
        - resourcedetection/system
        - transform/add_timestamp
        - transform/logs
        - batch
      exporters: [otlp/last9, debug]
    traces:
      receivers: [otlp]
      processors:
        - memory_limiter
        - resourcedetection/system
        - batch
      exporters: [otlp/last9]
  telemetry:
    logs:
      level: info
      encoding: json
EOF

# Set environment variables for OTEL Collector
echo "Configuring environment variables..."
cat > /etc/otelcol-contrib/otelcol-contrib.conf << EOF
OTEL_RESOURCE_ATTRIBUTES="${resource_attributes}"
EOF

# Enable and start OTEL Collector service
echo "Enabling and starting OTEL Collector service..."
systemctl daemon-reload
systemctl enable otelcol-contrib
systemctl start otelcol-contrib

# Wait for service to start
sleep 5

# Check service status
echo "Checking OTEL Collector service status..."
systemctl status otelcol-contrib --no-pager

# Verify health check endpoint
echo "Verifying health check endpoint..."
for i in {1..10}; do
  if curl -f http://localhost:13133 > /dev/null 2>&1; then
    echo "✅ OTEL Collector is healthy!"
    break
  else
    echo "Waiting for OTEL Collector to be healthy... (attempt $i/10)"
    sleep 5
  fi
done

echo "=========================================="
echo "OTEL Collector Installation Complete"
echo "=========================================="
echo "Service Status:"
systemctl status otelcol-contrib --no-pager

echo ""
echo "View logs with: sudo journalctl -u otelcol-contrib -f"
echo "Config file: /etc/otelcol-contrib/config.yaml"
echo "Health check: curl http://localhost:13133"
