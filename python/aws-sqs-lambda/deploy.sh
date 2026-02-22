#!/bin/bash
# Deploy the Lambda consumer with ADOT layer for OTel auto-instrumentation.
#
# Prerequisites:
#   - AWS CLI configured
#   - jq installed
#   - .env file created from .env.example
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh

set -e

if [ ! -f .env ]; then
    echo "Error: .env file not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# Safe .env loading (handles values with =, spaces, etc.)
set -o allexport
source .env
set +o allexport

echo "Packaging Lambda function..."
rm -f function.zip
rm -rf lambda_package && mkdir -p lambda_package
cd lambda_package

# Copy Lambda handler
cp ../lambda_function.py .

# Install dependencies into package directory
pip install --target . \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-propagator-aws-xray \
    --quiet

zip -r ../function.zip . -x "__pycache__/*" "*.pyc" --quiet
cd ..

echo "Creating IAM role..."
ROLE_NAME="${FUNCTION_NAME}-role"

cat > /tmp/trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --region "$AWS_REGION" \
    --query 'Role.Arn' --output text 2>/dev/null || \
    aws iam get-role \
    --role-name "$ROLE_NAME" \
    --query 'Role.Arn' --output text)

echo "Role ARN: $ROLE_ARN"

# Attach basic Lambda + SQS permissions
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole 2>/dev/null || true

echo "Waiting for IAM propagation (10s)..."
sleep 10

# Build environment variables JSON safely (handles = and special chars in values)
ENV_JSON=$(jq -n \
    --arg wrapper "/opt/otel-instrument" \
    --arg service "${OTEL_SERVICE_NAME:-lambda-consumer}" \
    --arg endpoint "$OTEL_EXPORTER_OTLP_ENDPOINT" \
    --arg headers "$OTEL_EXPORTER_OTLP_HEADERS" \
    '{Variables: {
        AWS_LAMBDA_EXEC_WRAPPER: $wrapper,
        OTEL_SERVICE_NAME: $service,
        OTEL_EXPORTER_OTLP_ENDPOINT: $endpoint,
        OTEL_EXPORTER_OTLP_HEADERS: $headers,
        OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf",
        OTEL_TRACES_EXPORTER: "otlp",
        OTEL_TRACES_SAMPLER: "always_on",
        OTEL_PROPAGATORS: "tracecontext,baggage"
    }}')

echo "Deploying Lambda function..."
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Function exists, updating code and configuration..."
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file fileb://function.zip \
        --region "$AWS_REGION" >/dev/null

    # Wait for code update to complete before updating config
    aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"

    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --layers "$ADOT_LAYER_ARN" \
        --environment "$ENV_JSON" >/dev/null
else
    echo "Creating new function..."
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$ROLE_ARN" \
        --handler lambda_function.handler \
        --zip-file fileb://function.zip \
        --timeout "${LAMBDA_TIMEOUT:-30}" \
        --memory-size "${LAMBDA_MEMORY:-256}" \
        --region "$AWS_REGION" \
        --layers "$ADOT_LAYER_ARN" \
        --tracing-config Mode=PassThrough \
        --environment "$ENV_JSON" >/dev/null
fi

echo ""
echo "Configuring SQS trigger..."
if [ -n "$SQS_QUEUE_ARN" ]; then
    aws lambda create-event-source-mapping \
        --function-name "$FUNCTION_NAME" \
        --event-source-arn "$SQS_QUEUE_ARN" \
        --batch-size 10 \
        --function-response-types ReportBatchItemFailures \
        --region "$AWS_REGION" 2>/dev/null || echo "Event source mapping already exists."
else
    echo "Skipping SQS trigger (SQS_QUEUE_ARN not set). Add it manually or set the var."
fi

# Cleanup
rm -rf lambda_package /tmp/trust-policy.json

echo ""
echo "Done! Lambda function deployed: $FUNCTION_NAME"
echo ""
echo "To test with a simulated SQS event:"
echo "  aws lambda invoke --function-name $FUNCTION_NAME --region $AWS_REGION \\"
echo "    --payload file://test-event.json response.json && cat response.json"
