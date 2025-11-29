#!/bin/bash

# Script to test Rails app and generate OpenTelemetry traces for Last9
# Make sure your Rails app is running on port 3000 before executing this script

BASE_URL="http://localhost:3000"

echo "🚀 Starting trace generation for Rails app..."
echo "   Sending requests to: $BASE_URL"
echo "   Make sure your Rails app is running with: rails server"
echo ""

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to make request and show status
make_request() {
    local method=$1
    local endpoint=$2
    local description=$3
    local data=$4

    echo -e "${BLUE}▶ $description${NC}"
    echo -e "  ${method} ${BASE_URL}${endpoint}"

    if [ "$method" == "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}${endpoint}" \
            -H "Content-Type: application/json" \
            -d "$data")
    else
        response=$(curl -s -w "\n%{http_code}" "${BASE_URL}${endpoint}")
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo -e "  ${GREEN}✓ Success (${http_code})${NC}"
    elif [ "$http_code" -ge 400 ] && [ "$http_code" -lt 500 ]; then
        echo -e "  ${YELLOW}⚠ Client Error (${http_code})${NC}"
    else
        echo -e "  ${RED}✗ Server Error (${http_code})${NC}"
    fi
    echo "  Response: $body"
    echo ""
    sleep 1
}

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 1: Basic Health Check${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
make_request "GET" "/health" "Health check endpoint"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 2: User List (Simulated DB Query)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
make_request "GET" "/users" "Get users list (with simulated DB latency)"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 3: Calculation with Custom Spans${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
make_request "GET" "/calculate?n=5" "Calculate Fibonacci(5)"
make_request "GET" "/calculate?n=8" "Calculate Fibonacci(8)"
make_request "GET" "/calculate?n=10" "Calculate Fibonacci(10)"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 4: Error Handling${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
make_request "GET" "/error" "Trigger an error (should create error trace)"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 5: Complex Order Processing (Nested Spans)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
make_request "POST" "/process_order" "Process order without ID" '{"items": ["item1", "item2"]}'
make_request "POST" "/process_order?order_id=ORD-12345" "Process order with ID" '{"items": ["item3", "item4"]}'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 6: External API Call Simulation${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
make_request "GET" "/external_api" "Simulate external API call"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test 7: Load Test (Multiple Rapid Requests)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Sending 10 rapid requests to generate load...${NC}"
for i in {1..10}; do
    echo -e "  Request $i/10"
    curl -s "${BASE_URL}/health" > /dev/null &
    curl -s "${BASE_URL}/users" > /dev/null &
    sleep 0.2
done
wait
echo -e "  ${GREEN}✓ Load test completed${NC}"
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ All tests completed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📊 Next steps:"
echo "1. Check your Last9 dashboard for traces"
echo "2. Look for service: 'ruby-on-rails-api-service'"
echo "3. You should see:"
echo "   - Request spans for each endpoint"
echo "   - Custom spans for calculations and order processing"
echo "   - Error traces from the /error endpoint"
echo "   - Latency measurements for each operation"
echo ""
echo "🔍 Trace details to look for in Last9:"
echo "   - HTTP request duration and status codes"
echo "   - Nested spans showing internal operations"
echo "   - Error stack traces (from /error endpoint)"
echo "   - Custom attributes (order IDs, calculation inputs, etc.)"