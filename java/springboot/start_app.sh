#!/bin/bash

# Script to start Spring Boot application with OpenTelemetry Java agent
# This script downloads the OpenTelemetry Java agent if not present and starts the app

OTEL_AGENT_VERSION="1.34.1"
OTEL_AGENT_JAR="otel-javaagent.jar"
OTEL_AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Spring Boot OpenTelemetry Application Starter${NC}"
echo ""

# Check if OpenTelemetry Java agent exists
if [ ! -f "$OTEL_AGENT_JAR" ]; then
    echo -e "${YELLOW}OpenTelemetry Java agent not found. Downloading...${NC}"
    echo -e "${YELLOW}URL: ${OTEL_AGENT_URL}${NC}"
    
    if curl -L -o "$OTEL_AGENT_JAR" "$OTEL_AGENT_URL"; then
        echo -e "${GREEN}✓ OpenTelemetry Java agent downloaded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to download OpenTelemetry Java agent${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ OpenTelemetry Java agent already exists${NC}"
fi

echo ""

# Set default OpenTelemetry environment variables if not already set
export OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME:-"springboot-otel-demo"}
export OTEL_RESOURCE_ATTRIBUTES=${OTEL_RESOURCE_ATTRIBUTES:-"service.name=springboot-otel-demo,service.version=1.0.0,deployment.environment=development"}

# Display current OpenTelemetry configuration
echo -e "${BLUE}OpenTelemetry Configuration:${NC}"
echo -e "${YELLOW}OTEL_SERVICE_NAME: ${OTEL_SERVICE_NAME}${NC}"
echo -e "${YELLOW}OTEL_RESOURCE_ATTRIBUTES: ${OTEL_RESOURCE_ATTRIBUTES}${NC}"
echo ""

# Check if specific OTEL endpoints are configured
if [ -n "$OTEL_EXPORTER_OTLP_ENDPOINT" ]; then
    echo -e "${GREEN}✓ OTLP Endpoint configured: ${OTEL_EXPORTER_OTLP_ENDPOINT}${NC}"
else
    echo -e "${YELLOW}⚠ No OTLP endpoint configured. Set OTEL_EXPORTER_OTLP_ENDPOINT to send data to your collector.${NC}"
fi

if [ -n "$OTEL_EXPORTER_JAEGER_ENDPOINT" ]; then
    echo -e "${GREEN}✓ Jaeger Endpoint configured: ${OTEL_EXPORTER_JAEGER_ENDPOINT}${NC}"
else
    echo -e "${YELLOW}⚠ No Jaeger endpoint configured. Set OTEL_EXPORTER_JAEGER_ENDPOINT to send traces to Jaeger.${NC}"
fi

if [ -n "$OTEL_METRICS_EXPORTER" ]; then
    echo -e "${GREEN}✓ Metrics Exporter configured: ${OTEL_METRICS_EXPORTER}${NC}"
else
    echo -e "${YELLOW}⚠ No metrics exporter configured. Set OTEL_METRICS_EXPORTER (e.g., otlp, prometheus)${NC}"
fi

if [ -n "$OTEL_LOGS_EXPORTER" ]; then
    echo -e "${GREEN}✓ Logs Exporter configured: ${OTEL_LOGS_EXPORTER}${NC}"
else
    echo -e "${YELLOW}⚠ No logs exporter configured. Set OTEL_LOGS_EXPORTER (e.g., otlp, logging)${NC}"
fi

echo ""

# Start the Spring Boot application
echo -e "${BLUE}Starting Spring Boot application with OpenTelemetry Java agent...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop the application${NC}"
echo ""

# Run the application with Maven and Java agent
mvn spring-boot:run \
    -Dspring-boot.run.jvmArguments="-javaagent:${OTEL_AGENT_JAR}" 