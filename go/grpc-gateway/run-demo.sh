#!/bin/bash

# Complete demo runner for gRPC-Gateway with DB and External APIs

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  gRPC-Gateway Enhanced Demo with DB & External APIs${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check environment variables
if [ -z "$OTEL_EXPORTER_OTLP_HEADERS" ]; then
    echo -e "${YELLOW}⚠️  OTEL_EXPORTER_OTLP_HEADERS not set${NC}"
    echo "   Please set OpenTelemetry environment variables first:"
    echo ""
    echo "   export OTEL_EXPORTER_OTLP_HEADERS=\"Authorization=Basic <YOUR_TOKEN>\""
    echo "   export OTEL_EXPORTER_OTLP_ENDPOINT=\"https://otlp-aps1.last9.io:443\""
    echo "   export OTEL_TRACES_SAMPLER=\"always_on\""
    echo "   export OTEL_RESOURCE_ATTRIBUTES=\"deployment.environment=local\""
    echo "   export OTEL_LOG_LEVEL=error"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Set database URL
export DATABASE_URL="${DATABASE_URL:-postgres://grpc_user:grpc_pass@localhost:5432/grpc_gateway?sslmode=disable}"

echo -e "${GREEN}✓${NC} Configuration loaded"
echo "  Service: grpc-gateway-enhanced"
echo "  Database: $DATABASE_URL"
echo "  OTLP Endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:-not set}"
echo ""

# Check if PostgreSQL is running
echo "Checking PostgreSQL..."
if docker-compose ps postgres 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✓${NC} PostgreSQL is running"
else
    echo -e "${YELLOW}⚠️  PostgreSQL is not running${NC}"
    echo "   Starting PostgreSQL..."
    ./setup-db.sh
fi

echo ""
echo -e "${BLUE}Starting services...${NC}"
echo ""

# Download dependencies
echo "Installing Go dependencies..."
go mod download
go mod tidy

echo ""
echo -e "${GREEN}✓${NC} Dependencies installed"
echo ""

# Set service name
export OTEL_SERVICE_NAME="grpc-gateway-enhanced"

echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
echo -e "${GREEN}  Server is starting...${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
echo ""
echo "Features enabled:"
echo "  ✓ gRPC Server (port 50051)"
echo "  ✓ HTTP Gateway (port 8080)"
echo "  ✓ PostgreSQL Database"
echo "  ✓ External API Calls (quotes, weather, user enrichment)"
echo "  ✓ OpenTelemetry Instrumentation"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Run the enhanced gateway
go run gateway-enhanced/main.go
