#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OTEL_AGENT_VERSION="2.13.3"
OTEL_AGENT_JAR="$SCRIPT_DIR/otel-javaagent.jar"
EXTENSION_JAR="$SCRIPT_DIR/last9-otel-body-capture.jar"
EXTENSION_SRC="/Users/prathamesh2_/Projects/java-otel-body-capture"

# Download OTel Java agent
if [ ! -f "$OTEL_AGENT_JAR" ]; then
    echo "Downloading OTel Java agent v${OTEL_AGENT_VERSION}..."
    curl -fL -o "$OTEL_AGENT_JAR" \
        "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar"
    echo "Done."
fi

# Build + copy the extension JAR
echo "Building last9-otel-body-capture extension..."
(cd "$EXTENSION_SRC" && gradle shadowJar --no-configuration-cache -q)
cp "$EXTENSION_SRC/lib/build/libs/lib-0.1.0.jar" "$EXTENSION_JAR"
echo "Extension JAR ready: $EXTENSION_JAR"

# Build the sample app
echo "Building sample app..."
(cd "$SCRIPT_DIR" && mvn package -q -DskipTests)

# Start with OTel agent + extension
exec java \
    -javaagent:"$OTEL_AGENT_JAR" \
    -Dotel.javaagent.extensions="$EXTENSION_JAR" \
    -Dotel.service.name=http-body-capture-jakarta-demo \
    -Dotel.exporter.otlp.endpoint=http://localhost:4319 \
    -Dotel.exporter.otlp.protocol=grpc \
    -Dotel.metrics.exporter=none \
    -Dotel.logs.exporter=none \
    -Dotel.bodycapture.enabled=true \
    -Dotel.bodycapture.capture_on_error_only=false \
    -jar "$SCRIPT_DIR/target/http-body-capture-jakarta-demo-1.0.0.jar"
