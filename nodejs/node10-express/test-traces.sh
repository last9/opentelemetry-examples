#!/bin/bash

# Test script to generate traces for Node 10 Express app

BASE_URL=${1:-http://localhost:3000}

echo "================================================="
echo "Testing Node 10 Express with OpenTelemetry"
echo "Base URL: $BASE_URL"
echo "================================================="
echo ""

# Test health endpoint
echo "1. Testing /health endpoint..."
curl -s $BASE_URL/health | jq .
echo ""

# Test root endpoint
echo "2. Testing / endpoint..."
curl -s $BASE_URL/ | jq .
echo ""

# Test custom span
echo "3. Testing /custom-span endpoint..."
curl -s $BASE_URL/custom-span | jq .
echo ""

# Test external call
echo "4. Testing /external-call endpoint..."
curl -s $BASE_URL/external-call | jq .
echo ""

# Test user endpoint
echo "5. Testing /users/:id endpoint..."
curl -s $BASE_URL/users/123 | jq .
echo ""

# Test slow endpoint
echo "6. Testing /slow endpoint..."
curl -s $BASE_URL/slow?delay=500 | jq .
echo ""

# Test error endpoint
echo "7. Testing /error endpoint (should fail)..."
curl -s $BASE_URL/error | jq .
echo ""

# Test 404
echo "8. Testing 404 endpoint..."
curl -s $BASE_URL/nonexistent | jq .
echo ""

echo "================================================="
echo "Test complete!"
echo "Check Last9 dashboard for traces"
echo "Service name: node10-express-example"
echo "================================================="
