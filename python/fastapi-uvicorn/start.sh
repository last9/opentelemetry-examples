#!/bin/bash

# Set OpenTelemetry environment variables
export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-fastapi-uvicorn-app}"
export OTEL_SERVICE_VERSION="${OTEL_SERVICE_VERSION:-1.0.0}"
export OTEL_RESOURCE_ATTRIBUTES="service.name=${OTEL_SERVICE_NAME},service.version=${OTEL_SERVICE_VERSION}"
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4317}"

# Start Circus with the configuration
echo "Starting FastAPI application with Circus (Uvicorn 2 workers) and OpenTelemetry auto-instrumentation..."
circusd circus.ini