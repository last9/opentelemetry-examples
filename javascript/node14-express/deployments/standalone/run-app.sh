#!/bin/bash
# =============================================================================
# Run Node.js App with Tail-Based Sampling (Standalone)
# =============================================================================
#
# Assumes the OTel Collector is running locally (installed via setup.sh).
# This script sets the correct environment and starts the app.
#
# Usage:
#   ./run-app.sh              # Run once
#   ./run-app.sh --daemon     # Run with nohup (background)

set -e

# Change to app directory
cd "$(dirname "$0")/../.."

# Configure app to send to local collector
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"
export OTEL_SERVICE_NAME="node14-express-example"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=production,host.name=$(hostname)"
export OTEL_TRACES_SAMPLER="always_on"  # Collector handles sampling
export PORT="${PORT:-3000}"

echo "Starting Node.js app..."
echo "Traces will be sent to local OTel Collector at ${OTEL_EXPORTER_OTLP_ENDPOINT}"
echo ""

if [ "$1" = "--daemon" ]; then
    nohup node -r ./instrumentation.js app.js > app.log 2>&1 &
    echo "App started in background. PID: $!"
    echo "Logs: tail -f app.log"
else
    node -r ./instrumentation.js app.js
fi
