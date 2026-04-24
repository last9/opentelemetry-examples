#!/usr/bin/env bash
# Deploys the AWS Cost Explorer collector as a Lambda function with a daily
# EventBridge schedule. Requires AWS CLI configured with sufficient permissions.
#
# Usage:
#   OTLP_HEADERS="Authorization=Basic <token>" ./deploy.sh
#
# Optional overrides:
#   FUNCTION_NAME=aws-cost-reporter   (default)
#   AWS_REGION=us-east-1              (default)
#   DAYS_BACK=30                      (default)
#   SCHEDULE=rate(1 day)              (default)
#   OTEL_SERVICE_NAME=aws-cost-reporter

set -euo pipefail

FUNCTION_NAME="${FUNCTION_NAME:-aws-cost-reporter}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DAYS_BACK="${DAYS_BACK:-30}"
SCHEDULE="${SCHEDULE:-rate(1 day)}"
OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-aws-cost-reporter}"
OTLP_ENDPOINT="${OTLP_ENDPOINT:-https://otlp.last9.io}"
ROLE_NAME="${FUNCTION_NAME}-role"

: "${OTLP_HEADERS:?OTLP_HEADERS is required. Set it to: Authorization=Basic <your-last9-token>}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "==> Deploying ${FUNCTION_NAME} to ${AWS_REGION}"

# ── 1. IAM role ────────────────────────────────────────────────────────────────

if ! aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
  echo "--> Creating IAM role ${ROLE_NAME}"
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null

  aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

  aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name cost-explorer-read \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": "ce:GetCostAndUsage",
        "Resource": "*"
      }]
    }'

  echo "--> Waiting for IAM role to propagate…"
  sleep 10
else
  echo "--> IAM role ${ROLE_NAME} already exists"
fi

# ── 2. Package Lambda ──────────────────────────────────────────────────────────

echo "--> Packaging Lambda"
BUILD_DIR=$(mktemp -d)
pip install --quiet -r requirements.txt -t "${BUILD_DIR}"
cp main.py "${BUILD_DIR}/"
(cd "${BUILD_DIR}" && zip -qr /tmp/aws-cost-reporter.zip .)
rm -rf "${BUILD_DIR}"

# ── 3. Deploy Lambda ───────────────────────────────────────────────────────────

ENV_VARS="Variables={OTLP_ENDPOINT=${OTLP_ENDPOINT},OTLP_HEADERS=${OTLP_HEADERS},OTEL_SERVICE_NAME=${OTEL_SERVICE_NAME},DAYS_BACK=${DAYS_BACK}}"

if aws lambda get-function --function-name "${FUNCTION_NAME}" --region "${AWS_REGION}" &>/dev/null; then
  echo "--> Updating Lambda function"
  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file fileb:///tmp/aws-cost-reporter.zip \
    --region "${AWS_REGION}" >/dev/null
  aws lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --environment "${ENV_VARS}" \
    --region "${AWS_REGION}" >/dev/null
else
  echo "--> Creating Lambda function"
  aws lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --runtime python3.13 \
    --role "${ROLE_ARN}" \
    --handler main.lambda_handler \
    --zip-file fileb:///tmp/aws-cost-reporter.zip \
    --timeout 300 \
    --memory-size 256 \
    --environment "${ENV_VARS}" \
    --region "${AWS_REGION}" >/dev/null
fi

FUNCTION_ARN=$(aws lambda get-function \
  --function-name "${FUNCTION_NAME}" \
  --region "${AWS_REGION}" \
  --query Configuration.FunctionArn \
  --output text)

# ── 4. EventBridge schedule ────────────────────────────────────────────────────

RULE_NAME="${FUNCTION_NAME}-schedule"

echo "--> Creating EventBridge rule: ${SCHEDULE}"
RULE_ARN=$(aws events put-rule \
  --name "${RULE_NAME}" \
  --schedule-expression "${SCHEDULE}" \
  --state ENABLED \
  --region "${AWS_REGION}" \
  --query RuleArn \
  --output text)

aws lambda add-permission \
  --function-name "${FUNCTION_NAME}" \
  --statement-id "${RULE_NAME}" \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn "${RULE_ARN}" \
  --region "${AWS_REGION}" 2>/dev/null || true

aws events put-targets \
  --rule "${RULE_NAME}" \
  --targets "Id=1,Arn=${FUNCTION_ARN}" \
  --region "${AWS_REGION}" >/dev/null

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "✓ Deployed ${FUNCTION_NAME}"
echo "  Function : ${FUNCTION_ARN}"
echo "  Schedule : ${SCHEDULE}"
echo "  Next run : $(aws events describe-rule --name "${RULE_NAME}" --region "${AWS_REGION}" --query ScheduleExpression --output text)"
echo ""
echo "Test now:"
echo "  aws lambda invoke --function-name ${FUNCTION_NAME} --region ${AWS_REGION} /tmp/out.json && cat /tmp/out.json"
