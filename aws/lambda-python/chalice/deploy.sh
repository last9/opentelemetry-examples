#!/usr/bin/env bash
set -euo pipefail

STAGE="${DEPLOY_STAGE:-dev}"

# Load environment variables
if [ -f .env ]; then
    set -a; source .env; set +a
    echo "Loaded .env"
else
    echo "No .env file found. Copy .env.example to .env and fill in values."
    exit 1
fi

# Update collector config with real credentials
sed "s|<YOUR_OTLP_ENDPOINT>|${OTLP_ENDPOINT}|g; s|Basic <YOUR_BASE64_CREDENTIALS>|${OTLP_AUTH_HEADER}|g" \
    collector-config.yaml > .chalice/collector-config.yaml

echo "Deploying to stage: ${STAGE}"
chalice deploy --stage "${STAGE}"

echo ""
echo "Deployment complete. Verify with:"
echo "  chalice url --stage ${STAGE}"
echo "  curl \$(chalice url --stage ${STAGE})"
echo ""
echo "Check traces in Last9 within 1-2 minutes."
