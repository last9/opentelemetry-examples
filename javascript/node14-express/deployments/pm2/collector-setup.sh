#!/bin/bash
# =============================================================================
# OTel Collector Setup for PM2/Standalone Deployments
# =============================================================================
#
# This script runs the OTel Collector as a Docker container on the same host
# as your PM2-managed Node.js application.
#
# Prerequisites:
# - Docker installed
# - Last9 credentials configured in .env
#
# Usage:
#   ./collector-setup.sh start   # Start collector
#   ./collector-setup.sh stop    # Stop collector
#   ./collector-setup.sh logs    # View collector logs
#   ./collector-setup.sh status  # Check if running

set -e

CONTAINER_NAME="otel-collector"
COLLECTOR_IMAGE="otel/opentelemetry-collector-contrib:0.118.0"
CONFIG_PATH="$(dirname "$0")/../../otel-collector-config.yaml"

# Load environment variables
if [ -f "$(dirname "$0")/../../.env" ]; then
    export $(grep -v '^#' "$(dirname "$0")/../../.env" | xargs)
fi

start_collector() {
    echo "Starting OTel Collector..."

    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Collector is already running"
        exit 0
    fi

    # Remove stopped container if exists
    docker rm -f ${CONTAINER_NAME} 2>/dev/null || true

    docker run -d \
        --name ${CONTAINER_NAME} \
        --restart unless-stopped \
        -p 4317:4317 \
        -p 4318:4318 \
        -v "${CONFIG_PATH}:/etc/otel-collector/config.yaml:ro" \
        -e LAST9_OTLP_ENDPOINT="${LAST9_OTLP_ENDPOINT}" \
        -e LAST9_AUTH_HEADER="${LAST9_AUTH_HEADER}" \
        ${COLLECTOR_IMAGE} \
        --config=/etc/otel-collector/config.yaml

    echo "Collector started on ports 4317 (gRPC) and 4318 (HTTP)"
    echo "App should use: OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318"
}

stop_collector() {
    echo "Stopping OTel Collector..."
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true
    echo "Collector stopped"
}

show_logs() {
    docker logs -f ${CONTAINER_NAME}
}

show_status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Collector is running"
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "Collector is not running"
        exit 1
    fi
}

case "${1:-}" in
    start)
        start_collector
        ;;
    stop)
        stop_collector
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {start|stop|logs|status}"
        exit 1
        ;;
esac
