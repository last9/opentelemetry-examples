#!/bin/bash

# Test script for Spring Boot application with OpenTelemetry
# This script will run all endpoints in a loop to generate telemetry data

BASE_URL="http://localhost:8080"
DELAY_BETWEEN_REQUESTS=2
LOOP_COUNT=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Spring Boot Application Test Script${NC}"
echo -e "${BLUE}Base URL: ${BASE_URL}${NC}"
echo -e "${BLUE}Loop Count: ${LOOP_COUNT}${NC}"
echo -e "${BLUE}Delay between requests: ${DELAY_BETWEEN_REQUESTS}s${NC}"
echo ""

# Function to make HTTP request and display result
make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    echo -e "${YELLOW}Testing: ${description}${NC}"
    echo -e "${YELLOW}Endpoint: ${method} ${endpoint}${NC}"
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "${BASE_URL}${endpoint}")
    elif [ "$method" = "POST" ]; then
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Content-Type: application/json" -d "$data" "${BASE_URL}${endpoint}")
    fi
    
    # Extract HTTP status code
    http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    response_body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 300 ]; then
        echo -e "${GREEN}✓ Success (${http_status})${NC}"
        echo -e "${GREEN}Response: ${response_body}${NC}"
    else
        echo -e "${RED}✗ Failed (${http_status})${NC}"
        echo -e "${RED}Response: ${response_body}${NC}"
    fi
    echo ""
}

# Function to run one complete test cycle
run_test_cycle() {
    local cycle=$1
    echo -e "${BLUE}=== Test Cycle ${cycle}/${LOOP_COUNT} ===${NC}"
    echo ""
    
    # Test GET endpoints
    make_request "GET" "/api/hello" "" "Hello World Endpoint"
    sleep $DELAY_BETWEEN_REQUESTS
    
    make_request "GET" "/api/health" "" "Health Check Endpoint"
    sleep $DELAY_BETWEEN_REQUESTS
    
    make_request "GET" "/api/products" "" "Get Products Endpoint"
    sleep $DELAY_BETWEEN_REQUESTS
    
    make_request "GET" "/api/products?limit=5" "" "Get Products with Limit"
    sleep $DELAY_BETWEEN_REQUESTS
    
    # Test user endpoints with different IDs
    local user_id=$((RANDOM % 100 + 1))
    make_request "GET" "/api/users/${user_id}" "" "Get User by ID (${user_id})"
    sleep $DELAY_BETWEEN_REQUESTS
    
    # Test POST endpoint
    local user_name="TestUser${cycle}"
    local user_email="testuser${cycle}@example.com"
    local post_data="{\"name\":\"${user_name}\",\"email\":\"${user_email}\"}"
    make_request "POST" "/api/users" "$post_data" "Create User"
    sleep $DELAY_BETWEEN_REQUESTS
    
    # Test error endpoint (this will fail, which is expected)
    make_request "GET" "/api/error-demo" "" "Error Demo Endpoint (Expected to fail)"
    sleep $DELAY_BETWEEN_REQUESTS
    
    # Test actuator endpoints
    make_request "GET" "/actuator/health" "" "Actuator Health"
    sleep $DELAY_BETWEEN_REQUESTS
    
    make_request "GET" "/actuator/metrics" "" "Actuator Metrics"
    sleep $DELAY_BETWEEN_REQUESTS
    
    echo -e "${GREEN}✓ Completed Test Cycle ${cycle}${NC}"
    echo ""
}

# Check if the application is running
echo -e "${YELLOW}Checking if application is running...${NC}"
if curl -s "${BASE_URL}/api/health" > /dev/null; then
    echo -e "${GREEN}✓ Application is running${NC}"
else
    echo -e "${RED}✗ Application is not running. Please start the Spring Boot application first.${NC}"
    echo -e "${YELLOW}You can start it with: mvn spring-boot:run${NC}"
    exit 1
fi
echo ""

# Run test cycles
for i in $(seq 1 $LOOP_COUNT); do
    run_test_cycle $i
    
    # Add a longer delay between cycles
    if [ $i -lt $LOOP_COUNT ]; then
        echo -e "${BLUE}Waiting 5 seconds before next cycle...${NC}"
        sleep 5
        echo ""
    fi
done

echo -e "${GREEN}✓ All test cycles completed!${NC}"
echo -e "${BLUE}Check your OpenTelemetry collector/backend for telemetry data.${NC}" 