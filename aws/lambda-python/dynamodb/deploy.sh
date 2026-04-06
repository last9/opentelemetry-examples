#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

STAGE=${DEPLOY_STAGE:-dev}
TABLE=${DYNAMODB_TABLE:-items}
REGION=${AWS_REGION:-ap-south-1}

echo "==> Deploying stage: $STAGE"

# 1. Create DynamoDB table if it doesn't exist
echo "==> Ensuring DynamoDB table '$TABLE' exists..."
aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" > /dev/null 2>&1 || \
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"
echo "    Table ready."

# 2. Inject Last9 credentials into collector config
echo "==> Updating collector config..."
sed \
  -e "s|<YOUR_OTLP_ENDPOINT>|${OTLP_ENDPOINT}|g" \
  -e "s|Basic <your-base64-credentials>|${OTLP_AUTH_HEADER}|g" \
  .chalice/collector-config.yaml > /tmp/collector-config-resolved.yaml
cp /tmp/collector-config-resolved.yaml .chalice/collector-config.yaml

# 3. Deploy with Chalice
echo "==> Running chalice deploy..."
chalice deploy --stage "$STAGE"

echo ""
echo "Deployment complete. Traces will appear in Last9 within 1-2 minutes."
