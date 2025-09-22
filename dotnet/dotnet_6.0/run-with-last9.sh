#!/bin/bash

# Last9 OpenTelemetry Configuration
export OTEL_DOTNET_AUTO_INSTRUMENTATION_ENABLED=true
export OTEL_SERVICE_NAME="dotnet-test-app"
export OTEL_TRACES_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp-aps1.last9.io:443"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_LAST9_TOKEN_HERE"
export OTEL_TRACES_SAMPLER="always_on"
export OTEL_LOG_LEVEL=error
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"

echo "=== Last9 OpenTelemetry Configuration ==="
echo "Service Name: $OTEL_SERVICE_NAME"
echo "OTLP Endpoint: $OTEL_EXPORTER_OTLP_ENDPOINT"
echo "Resource Attributes: $OTEL_RESOURCE_ATTRIBUTES"
echo "=========================================="
echo ""

# Add .NET to PATH if not already there
export PATH="$HOME/.dotnet:$PATH"

# Run the application
dotnet run
