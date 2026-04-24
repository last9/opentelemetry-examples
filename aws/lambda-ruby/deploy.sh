#!/bin/bash

# Ruby Lambda Deployment Script
# Deploys a Ruby Lambda function with OpenTelemetry instrumentation to Last9.

set -e

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found. Copy .env.example to .env and fill in your values."
  exit 1
fi

: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION not set}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID not set}"
: "${FUNCTION_NAME:?FUNCTION_NAME not set}"
: "${LAMBDA_ROLE_NAME:?LAMBDA_ROLE_NAME not set}"
: "${OTEL_EXPORTER_OTLP_ENDPOINT:?OTEL_EXPORTER_OTLP_ENDPOINT not set}"
: "${OTEL_EXPORTER_OTLP_HEADERS:?OTEL_EXPORTER_OTLP_HEADERS not set}"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

echo "📦 Installing gems into vendor/bundle (Lambda-compatible)..."
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test'
bundle install

echo "📦 Creating deployment package..."
zip -qr function.zip lambda_function.rb setup_otel.rb Gemfile Gemfile.lock vendor/

echo "🔐 Ensuring IAM role exists..."
if ! aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" --region "${AWS_DEFAULT_REGION}" &>/dev/null; then
  cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF
  aws iam create-role \
    --role-name "${LAMBDA_ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/trust-policy.json

  aws iam attach-role-policy \
    --role-name "${LAMBDA_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

  echo "Waiting for IAM role to propagate..."
  sleep 10
fi

ENV_VARS="Variables={\
OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME:-ruby-lambda-example},\
OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT},\
OTEL_EXPORTER_OTLP_HEADERS=${OTEL_EXPORTER_OTLP_HEADERS},\
OTEL_EXPORTER_OTLP_PROTOCOL=${OTEL_EXPORTER_OTLP_PROTOCOL:-http/protobuf},\
OTEL_TRACES_SAMPLER=${OTEL_TRACES_SAMPLER:-always_on},\
OTEL_PROPAGATORS=${OTEL_PROPAGATORS:-tracecontext,baggage,xray},\
OTEL_RESOURCE_ATTRIBUTES=${OTEL_RESOURCE_ATTRIBUTES:-deployment.environment=production}\
}"

if aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${AWS_DEFAULT_REGION}" &>/dev/null; then
  echo "🔄 Updating existing function..."
  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file fileb://function.zip \
    --region "${AWS_DEFAULT_REGION}"

  aws lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --environment "${ENV_VARS}" \
    --region "${AWS_DEFAULT_REGION}"
else
  echo "🚀 Creating Lambda function..."
  aws lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --runtime ruby3.2 \
    --role "${ROLE_ARN}" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment "${ENV_VARS}" \
    --region "${AWS_DEFAULT_REGION}"
fi

echo ""
echo "✅ Deployed ${FUNCTION_NAME} to ${AWS_DEFAULT_REGION}"
echo ""
echo "Test with:"
echo "  aws lambda invoke --function-name ${FUNCTION_NAME} --region ${AWS_DEFAULT_REGION} --payload '{}' response.json && cat response.json"
echo ""
echo "View traces at: https://app.last9.io/traces"
