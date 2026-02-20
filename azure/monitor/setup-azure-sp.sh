#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUBSCRIPTION_ID=${1:-$(az account show --query id -o tsv)}
SP_NAME="last9-metrics-collector"

echo -e "${GREEN}Creating Azure Service Principal for Last9 metrics collection${NC}"
echo "Subscription: $SUBSCRIPTION_ID"
echo "Service Principal: $SP_NAME"
echo ""

# Create SP with Monitoring Reader — read-only, no write access to any resources
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role "Monitoring Reader" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --output json)

CLIENT_ID=$(echo $SP_OUTPUT | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
CLIENT_SECRET=$(echo $SP_OUTPUT | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
TENANT_ID=$(echo $SP_OUTPUT | python3 -c "import sys,json; print(json.load(sys.stdin)['tenant'])")

echo -e "${GREEN}Service principal created. Add these to your .env:${NC}"
echo ""
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "AZURE_CLIENT_ID=$CLIENT_ID"
echo "AZURE_CLIENT_SECRET=$CLIENT_SECRET"
echo ""
echo -e "${YELLOW}Note: The service principal has Monitoring Reader role only — read-only access to metrics. No write permissions granted.${NC}"
