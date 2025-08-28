#!/bin/bash

# Quick Start Script for Spring Boot OpenTelemetry Demo
# This script sets up the entire environment and starts the application

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Spring Boot OpenTelemetry Demo - Quick Start${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check Java
if ! command -v java &> /dev/null; then
    echo -e "${RED}✗ Java is not installed. Please install Java 17 or higher.${NC}"
    exit 1
fi

java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$java_version" -lt 17 ]; then
    echo -e "${RED}✗ Java version $java_version is too old. Please install Java 17 or higher.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Java version: $(java -version 2>&1 | head -n 1)${NC}"

# Check Maven
if ! command -v mvn &> /dev/null; then
    echo -e "${RED}✗ Maven is not installed. Please install Maven 3.6 or higher.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Maven version: $(mvn -version | head -n 1)${NC}"

# Check Docker (optional)
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ Docker is available${NC}"
    DOCKER_AVAILABLE=true
else
    echo -e "${YELLOW}⚠ Docker not found. You can still run the app with console exporters.${NC}"
    DOCKER_AVAILABLE=false
fi

# Check curl
if ! command -v curl &> /dev/null; then
    echo -e "${RED}✗ curl is not installed. Please install curl for the test script.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ curl is available${NC}"

echo ""

# Make scripts executable
echo -e "${YELLOW}Setting up scripts...${NC}"
chmod +x start_app.sh test_script.sh
echo -e "${GREEN}✓ Scripts are executable${NC}"

echo ""

# Ask user for configuration
echo -e "${BLUE}Configuration Options:${NC}"
echo "1. Console only (logs to console)"
echo "2. Local OpenTelemetry Collector (requires Docker)"
echo "3. Custom configuration"
echo ""

read -p "Choose option (1-3): " choice

case $choice in
    1)
        echo -e "${YELLOW}Setting up console-only configuration...${NC}"
        export OTEL_TRACES_EXPORTER=logging
        export OTEL_METRICS_EXPORTER=logging
        export OTEL_LOGS_EXPORTER=logging
        ;;
    2)
        if [ "$DOCKER_AVAILABLE" = false ]; then
            echo -e "${RED}Docker is required for this option. Falling back to console-only.${NC}"
            export OTEL_TRACES_EXPORTER=logging
            export OTEL_METRICS_EXPORTER=logging
            export OTEL_LOGS_EXPORTER=logging
        else
            echo -e "${YELLOW}Starting OpenTelemetry Collector with Docker...${NC}"
            docker-compose up -d otel-collector jaeger prometheus grafana
            echo -e "${GREEN}✓ OpenTelemetry infrastructure started${NC}"
            
            # Wait for services to be ready
            echo -e "${YELLOW}Waiting for services to be ready...${NC}"
            sleep 10
            
            export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
            export OTEL_TRACES_EXPORTER=otlp
            export OTEL_METRICS_EXPORTER=otlp
            export OTEL_LOGS_EXPORTER=otlp
        fi
        ;;
    3)
        echo -e "${YELLOW}Please set your custom environment variables:${NC}"
        echo "Example:"
        echo "export OTEL_EXPORTER_OTLP_ENDPOINT=http://your-collector:4317"
        echo "export OTEL_TRACES_EXPORTER=otlp"
        echo "export OTEL_METRICS_EXPORTER=otlp"
        echo "export OTEL_LOGS_EXPORTER=otlp"
        echo ""
        echo "Press Enter when ready to continue..."
        read
        ;;
    *)
        echo -e "${RED}Invalid choice. Using console-only configuration.${NC}"
        export OTEL_TRACES_EXPORTER=logging
        export OTEL_METRICS_EXPORTER=logging
        export OTEL_LOGS_EXPORTER=logging
        ;;
esac

# Set default service configuration
export OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME:-"springboot-otel-demo"}
export OTEL_RESOURCE_ATTRIBUTES=${OTEL_RESOURCE_ATTRIBUTES:-"service.name=springboot-otel-demo,service.version=1.0.0,deployment.environment=development"}

echo ""
echo -e "${BLUE}Final Configuration:${NC}"
echo -e "${YELLOW}OTEL_SERVICE_NAME: ${OTEL_SERVICE_NAME}${NC}"
echo -e "${YELLOW}OTEL_RESOURCE_ATTRIBUTES: ${OTEL_RESOURCE_ATTRIBUTES}${NC}"
echo -e "${YELLOW}OTEL_TRACES_EXPORTER: ${OTEL_TRACES_EXPORTER}${NC}"
echo -e "${YELLOW}OTEL_METRICS_EXPORTER: ${OTEL_METRICS_EXPORTER}${NC}"
echo -e "${YELLOW}OTEL_LOGS_EXPORTER: ${OTEL_LOGS_EXPORTER}${NC}"

if [ -n "$OTEL_EXPORTER_OTLP_ENDPOINT" ]; then
    echo -e "${YELLOW}OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT}${NC}"
fi

echo ""

# Start the application
echo -e "${BLUE}Starting Spring Boot application...${NC}"
echo -e "${YELLOW}The application will start in the background.${NC}"
echo -e "${YELLOW}Check the logs for startup information.${NC}"
echo ""

# Start the application in the background
./start_app.sh &
APP_PID=$!

# Wait for application to start
echo -e "${YELLOW}Waiting for application to start...${NC}"
sleep 30

# Check if application is running
if curl -s http://localhost:8080/api/health > /dev/null; then
    echo -e "${GREEN}✓ Application is running on http://localhost:8080${NC}"
else
    echo -e "${RED}✗ Application failed to start. Check the logs above.${NC}"
    kill $APP_PID 2>/dev/null
    exit 1
fi

echo ""
echo -e "${BLUE}🎉 Setup Complete!${NC}"
echo ""
echo -e "${GREEN}Application URLs:${NC}"
echo -e "${YELLOW}  Main App: http://localhost:8080${NC}"
echo -e "${YELLOW}  Health Check: http://localhost:8080/api/health${NC}"
echo -e "${YELLOW}  Actuator: http://localhost:8080/actuator${NC}"
echo -e "${YELLOW}  Prometheus Metrics: http://localhost:8080/actuator/prometheus${NC}"

if [ "$DOCKER_AVAILABLE" = true ] && [ "$choice" = "2" ]; then
    echo ""
    echo -e "${GREEN}Monitoring URLs:${NC}"
    echo -e "${YELLOW}  Jaeger UI: http://localhost:16686${NC}"
    echo -e "${YELLOW}  Prometheus: http://localhost:9090${NC}"
    echo -e "${YELLOW}  Grafana: http://localhost:3000 (admin/admin)${NC}"
fi

echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo -e "${YELLOW}  1. Run the test script: ./test_script.sh${NC}"
echo -e "${YELLOW}  2. Check your telemetry backend for data${NC}"
echo -e "${YELLOW}  3. Press Ctrl+C to stop the application${NC}"
echo ""

# Keep the script running
wait $APP_PID 