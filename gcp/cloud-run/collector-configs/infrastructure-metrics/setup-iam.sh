#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ID=${1:-$(gcloud config get-value project)}
SERVICE_ACCOUNT_NAME="metrics-collector"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${GREEN}Setting up IAM for Cloud Run Metrics Collector${NC}"
echo "Project ID: $PROJECT_ID"
echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
echo ""

# Check if service account exists
if gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL --project=$PROJECT_ID >/dev/null 2>&1; then
    echo -e "${YELLOW}Service account already exists${NC}"
else
    echo -e "${GREEN}Creating service account...${NC}"
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Cloud Run Metrics Collector" \
        --description="Service account for collecting GCP Cloud Run metrics via Cloud Monitoring API" \
        --project=$PROJECT_ID
fi

# Grant Cloud Monitoring Viewer role (to read metrics)
echo -e "${GREEN}Granting monitoring.viewer role...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/monitoring.viewer" \
    --condition=None

# Grant Secret Accessor role (to read Last9 credentials)
echo -e "${GREEN}Granting secretmanager.secretAccessor role...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None

echo ""
echo -e "${GREEN}✅ IAM setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Store Last9 credentials in Secret Manager:"
echo "   echo -n 'Authorization=Basic YOUR_CREDENTIALS' | \\"
echo "     gcloud secrets create last9-auth-header --data-file=-"
echo ""
echo "2. Deploy the collector:"
echo "   gcloud builds submit --config cloudbuild.yaml"
