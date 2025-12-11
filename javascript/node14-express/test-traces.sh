#!/bin/bash

# Test script for Node 14 Express OpenTelemetry example
# Generates test traffic to verify traces

BASE_URL=${1:-http://localhost:3000}

echo "========================================="
echo "Testing Node 14 Express with OpenTelemetry"
echo "Base URL: $BASE_URL"
echo "========================================="
echo ""

echo "1. Testing health endpoint..."
curl -s $BASE_URL/health | jq . || curl -s $BASE_URL/health
echo ""

echo "2. Testing hello endpoint..."
curl -s $BASE_URL/ | jq . || curl -s $BASE_URL/
echo ""

echo "3. Testing custom span..."
curl -s $BASE_URL/custom-span | jq . || curl -s $BASE_URL/custom-span
echo ""

echo "4. Testing external API call..."
curl -s $BASE_URL/external-call | jq . || curl -s $BASE_URL/external-call
echo ""

echo "5. Testing user lookup..."
curl -s $BASE_URL/users/123 | jq . || curl -s $BASE_URL/users/123
echo ""

echo "6. Testing slow endpoint..."
curl -s "$BASE_URL/slow?delay=500" | jq . || curl -s "$BASE_URL/slow?delay=500"
echo ""

echo "7. Testing error endpoint..."
curl -s $BASE_URL/error | jq . || curl -s $BASE_URL/error
echo ""

echo "========================================="
echo "Test complete! Check Last9 dashboard for traces"
echo "Service name: node14-express-example"
echo "========================================="
