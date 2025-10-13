#!/bin/bash

# Example script to query Last9 API with PromQL
# Usage: ./example.sh ORG_SLUG API_TOKEN

set -e

# Check if required parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 ORG_SLUG API_TOKEN"
    echo "Example: $0 mlpgaming YOUR_API_TOKEN_HERE"
    echo ""
    echo "Get your API token from: https://app.last9.io"
    echo "Go to Profile Settings > API Tokens"
    exit 1
fi

ORG_SLUG="$1"
API_TOKEN="$2"

echo "🔍 Querying Last9 API for organization: $ORG_SLUG"
echo "=================================================="

# Step 1: Get organization info to find org ID
echo "📋 Getting organization info..."
ORG_INFO=$(curl --silent --location --request GET \
    "https://app.last9.io/api/v4/organizations/$ORG_SLUG" \
    --header "X-LAST9-API-TOKEN: Bearer $API_TOKEN")

if echo "$ORG_INFO" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Error getting organization info:"
    echo "$ORG_INFO" | jq -r '.error'
    exit 1
fi

ORG_ID=$(echo "$ORG_INFO" | jq -r '.id')
echo "✅ Organization ID: $ORG_ID"

# Step 2: Get datasources for the organization
echo "📊 Getting datasources..."
DATASOURCES=$(curl --silent --location --request GET \
    "https://app.last9.io/api/v4/organizations/$ORG_SLUG/datasources" \
    --header "X-LAST9-API-TOKEN: Bearer $API_TOKEN")

if echo "$DATASOURCES" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Error getting datasources:"
    echo "$DATASOURCES" | jq -r '.error'
    exit 1
fi

# Get the first datasource UID
DATASOURCE_UID=$(echo "$DATASOURCES" | jq -r '.[0].id')
DATASOURCE_NAME=$(echo "$DATASOURCES" | jq -r '.[0].name')
echo "✅ Datasource: $DATASOURCE_NAME (UID: $DATASOURCE_UID)"

# Step 3: Generate Grafana URL
GRAFANA_URL="https://app.last9.io/api/gp/explore?orgId=$ORG_ID&datasource=$DATASOURCE_UID"
echo "🔗 Grafana URL: $GRAFANA_URL"

# Step 4: Execute PromQL query
echo "🚀 Executing PromQL query..."
PROMQL_QUERY='jvm_buffer_count_buffers{application="service-data-feature-store-realtime", namespace="data-engineering", pod="data-feature-store-realtime-high-0"}'

# URL encode the PromQL query
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PROMQL_QUERY'))")

# Get current timestamp for time range (last 1 hour)
CURRENT_TIME=$(date +%s)
START_TIME=$((CURRENT_TIME - 3600))  # 1 hour ago
END_TIME=$CURRENT_TIME

echo "⏰ Time range: $(date -d @$START_TIME) to $(date -d @$END_TIME)"

# Execute the query
QUERY_URL="https://app.last9.io/api/gp/api/datasources/uid/$DATASOURCE_UID/resources/api/v1/query"
QUERY_PARAMS="query=$ENCODED_QUERY&start=$START_TIME&end=$END_TIME"

echo "🔍 Query URL: $QUERY_URL"
echo "📝 PromQL: $PROMQL_QUERY"

# Make the query request
QUERY_RESPONSE=$(curl --silent --location --request GET \
    "$QUERY_URL?$QUERY_PARAMS" \
    --header "X-LAST9-API-TOKEN: Bearer $API_TOKEN" \
    --header "accept: application/json")

# Check if query was successful
if echo "$QUERY_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Query failed:"
    echo "$QUERY_RESPONSE" | jq -r '.error'
    exit 1
fi

# Display results
echo "✅ Query successful!"
echo "📊 Results:"
echo "$QUERY_RESPONSE" | jq '.'

# Save results to file
OUTPUT_FILE="reports/${ORG_SLUG}_promql_query_$(date +%Y%m%d_%H%M%S).json"
mkdir -p reports
echo "$QUERY_RESPONSE" > "$OUTPUT_FILE"
echo "💾 Results saved to: $OUTPUT_FILE"

echo ""
echo "=================================================="
echo "✅ SUCCESS"
echo "=================================================="
echo "🔗 Grafana URL: $GRAFANA_URL"
echo "📁 Results file: $OUTPUT_FILE"
