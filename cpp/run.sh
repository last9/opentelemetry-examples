#!/bin/bash

# Script to build and run the OpenTelemetry C++ sample application

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please create a .env file with the following variables:"
    echo "  OTEL_EXPORTER_OTLP_ENDPOINT=<your last9 endpoint>"
    echo "  OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your-key>"
    echo "  OTEL_SERVICE_NAME=cpp-sample-app"
    echo "  DEPLOYMENT_ENVIRONMENT=local"
    exit 1
fi

echo "=== Building OpenTelemetry C++ Sample Application ==="
echo "This may take several minutes on first build..."
echo ""

# Build the Docker image
docker build -t cpp-otel-sample .

echo ""
echo "=== Running the application ==="
echo ""

# Run the container with environment variables from .env
docker run --rm --env-file .env cpp-otel-sample

echo ""
echo "=== Application completed ==="
