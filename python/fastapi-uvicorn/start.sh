#!/bin/bash

# Set OpenTelemetry environment variables
export OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-fastapi-uvicorn-app}"
export OTEL_SERVICE_VERSION="${OTEL_SERVICE_VERSION:-1.0.0}"
export OTEL_RESOURCE_ATTRIBUTES="service.name=${OTEL_SERVICE_NAME},service.version=${OTEL_SERVICE_VERSION}"

# Check if OTEL_EXPORTER_OTLP_ENDPOINT is set for production/instrumented mode
if [ -n "$OTEL_EXPORTER_OTLP_ENDPOINT" ]; then
    # Production mode: use gunicorn with uvicorn worker and opentelemetry-instrument
    echo "OTEL endpoint detected. Starting with gunicorn + uvicorn worker + auto instrumentation..."
    export OTEL_TRACES_EXPORTER="${OTEL_TRACES_EXPORTER:-console}"
    opentelemetry-instrument gunicorn app:app -c gunicorn.conf.py
else
    # Local development mode: use simple python app.py
    echo "Local development mode. Starting with simple uvicorn..."
    python app.py
fi