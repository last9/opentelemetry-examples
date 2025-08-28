#!/bin/bash

# Default values
OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-https://otlp.last9.io}
OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME:-tomcat-otel-example}
OTEL_EXPORTER_OTLP_HEADERS=${OTEL_EXPORTER_OTLP_HEADERS:-""}

# If username and password are provided, add them to the headers
if [ ! -z "$OTEL_EXPORTER_OTLP_USERNAME" ] && [ ! -z "$OTEL_EXPORTER_OTLP_PASSWORD" ]; then
    encoded_credentials=$(echo -n "$OTEL_EXPORTER_OTLP_USERNAME:$OTEL_EXPORTER_OTLP_PASSWORD" | base64)
    OTEL_EXPORTER_OTLP_HEADERS="authorization=Basic $encoded_credentials,$OTEL_EXPORTER_OTLP_HEADERS"
fi

# Trim trailing comma if present
OTEL_EXPORTER_OTLP_HEADERS=${OTEL_EXPORTER_OTLP_HEADERS%,}

# OpenTelemetry configuration
export OTEL_EXPORTER_OTLP_ENDPOINT
export OTEL_SERVICE_NAME
export OTEL_TRACES_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_HEADERS
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_METRIC_EXPORT_INTERVAL=60000

# Additional debug logging
export OTEL_JAVAAGENT_DEBUG=true

# Start Tomcat with OpenTelemetry Java agent
## Works for Mac

export CATALINA_OPTS="$CATALINA_OPTS -javaagent:$PWD/opentelemetry-javaagent.jar"
/opt/homebrew/opt/tomcat/bin/catalina run

## For other OS, you may need to use the full path to the catalina script