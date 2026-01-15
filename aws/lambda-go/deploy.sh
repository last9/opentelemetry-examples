#!/bin/bash

# Go Lambda Deployment Script
# This script deploys a Go Lambda function with OpenTelemetry instrumentation

set -e

# Load environment variables (copy .env.example to .env and update values)
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found. Please create it from .env.example"
    exit 1
fi

echo "📦 Installing Go dependencies..."
go mod tidy

echo "🔨 Building Go Lambda function for Linux AMD64..."
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go

if [ $? -ne 0 ]; then
  echo "❌ Build failed"
  exit 1
fi

echo "📦 Creating Lambda deployment package..."
zip -q function.zip bootstrap collector-config.yaml

if [ $? -ne 0 ]; then
  echo "❌ Failed to create zip"
  exit 1
fi

echo "Creating IAM role for Lambda..."
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role
ROLE_NAME="${FUNCTION_NAME}-role"
ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'Role.Arn' \
    --output text 2>/dev/null || \
    aws iam get-role \
    --role-name "$ROLE_NAME" \
    --profile "$AWS_PROFILE" \
    --query 'Role.Arn' \
    --output text)

echo "IAM Role ARN: $ROLE_ARN"

echo "Creating IAM policy for CloudWatch Logs..."
cat > lambda-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:${AWS_REGION}:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${AWS_REGION}:*:log-group:/aws/lambda/${FUNCTION_NAME}:*"
      ]
    }
  ]
}
EOF

# Create and attach policy
POLICY_NAME="${FUNCTION_NAME}-cloudwatch-policy"
POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file://lambda-policy.json \
    --profile "$AWS_PROFILE" \
    --query 'Policy.Arn' \
    --output text 2>/dev/null || \
    aws iam list-policies \
    --profile "$AWS_PROFILE" \
    --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" \
    --output text)

echo "Policy ARN: $POLICY_ARN"

# Attach policy to role
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" \
    --profile "$AWS_PROFILE" 2>/dev/null || true

echo "Waiting for IAM role to propagate (10 seconds)..."
sleep 10

echo "☁️  Creating Lambda function..."
aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$LAMBDA_RUNTIME" \
    --role "$ROLE_ARN" \
    --handler bootstrap \
    --zip-file fileb://function.zip \
    --timeout "$LAMBDA_TIMEOUT" \
    --memory-size "$LAMBDA_MEMORY" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --layers "$OTEL_LAYER_ARN" \
    --tracing-config Mode=PassThrough \
    --environment "Variables={
        OTEL_SERVICE_NAME=$OTEL_SERVICE_NAME,
        OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_EXPORTER_OTLP_ENDPOINT,
        OTEL_EXPORTER_OTLP_HEADERS=$OTEL_EXPORTER_OTLP_HEADERS,
        OTEL_EXPORTER_OTLP_PROTOCOL=$OTEL_EXPORTER_OTLP_PROTOCOL,
        OTEL_RESOURCE_ATTRIBUTES=$OTEL_RESOURCE_ATTRIBUTES,
        OTEL_TRACES_EXPORTER=$OTEL_TRACES_EXPORTER,
        OTEL_TRACES_SAMPLER=$OTEL_TRACES_SAMPLER,
        OTEL_PROPAGATORS=$OTEL_PROPAGATORS,
        OPENTELEMETRY_COLLECTOR_CONFIG_FILE=/var/task/collector-config.yaml
    }" \
    --architectures x86_64

echo ""
echo "✅ Lambda function deployed successfully!"
echo "Function Name: $FUNCTION_NAME"
echo "Region: $AWS_REGION"
echo "Runtime: $LAMBDA_RUNTIME"
echo ""
echo "🧪 To test the function, run:"
echo "aws lambda invoke --function-name $FUNCTION_NAME --region $AWS_REGION --profile $AWS_PROFILE --payload '{\"name\":\"Last9\",\"message\":\"Testing Go Lambda with OTel\"}' response.json && cat response.json"

# Cleanup
rm -f trust-policy.json lambda-policy.json
