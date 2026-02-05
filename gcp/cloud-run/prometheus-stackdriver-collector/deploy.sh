#!/bin/bash
set -e

# Deployment script for GCP Cloud Run Metrics Collector
# This script automates the entire deployment process

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}GCP Cloud Run Metrics Collector Deployment${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if required tools are installed
command -v gcloud >/dev/null 2>&1 || { echo -e "${RED}Error: gcloud CLI is not installed${NC}"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: docker is not installed${NC}"; exit 1; }

# Get project ID
PROJECT_ID=${1:-$(gcloud config get-value project)}
if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: PROJECT_ID not set${NC}"
  echo "Usage: ./deploy.sh PROJECT_ID REGION REMOTE_WRITE_URL"
  exit 1
fi

# Get region
REGION=${2:-us-central1}

# Get remote write URL
REMOTE_WRITE_URL=${3}
if [ -z "$REMOTE_WRITE_URL" ]; then
  echo -e "${RED}Error: REMOTE_WRITE_URL not provided${NC}"
  echo "Usage: ./deploy.sh PROJECT_ID REGION REMOTE_WRITE_URL"
  echo ""
  echo "Example:"
  echo "  ./deploy.sh my-project us-central1 your-remote-write-url"
  exit 1
fi

SERVICE_NAME="cloud-run-prometheus-collector"
SERVICE_ACCOUNT="metrics-collector@${PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${GREEN}Configuration:${NC}"
echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Service Name: $SERVICE_NAME"
echo "  Remote Write URL: $REMOTE_WRITE_URL"
echo ""

# Step 1: Create service account if it doesn't exist
echo -e "${YELLOW}[1/6] Checking service account...${NC}"
if gcloud iam service-accounts describe $SERVICE_ACCOUNT --project=$PROJECT_ID >/dev/null 2>&1; then
  echo -e "${GREEN}✓ Service account already exists${NC}"
else
  echo "Creating service account..."
  gcloud iam service-accounts create metrics-collector \
    --display-name="Cloud Run Metrics Collector" \
    --description="Collects GCP Cloud Run metrics and forwards to Last9" \
    --project=$PROJECT_ID
  echo -e "${GREEN}✓ Service account created${NC}"
fi

# Step 2: Grant IAM permissions
echo -e "${YELLOW}[2/6] Granting IAM permissions...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/monitoring.viewer" \
  --condition=None \
  >/dev/null 2>&1

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor" \
  --condition=None \
  >/dev/null 2>&1
echo -e "${GREEN}✓ IAM permissions granted${NC}"

# Step 3: Check secrets
echo -e "${YELLOW}[3/6] Checking Last9 credentials in Secret Manager...${NC}"
SECRET_MISSING=0
if ! gcloud secrets describe last9-username --project=$PROJECT_ID >/dev/null 2>&1; then
  echo -e "${RED}✗ Secret 'last9-username' not found${NC}"
  SECRET_MISSING=1
fi
if ! gcloud secrets describe last9-password --project=$PROJECT_ID >/dev/null 2>&1; then
  echo -e "${RED}✗ Secret 'last9-password' not found${NC}"
  SECRET_MISSING=1
fi

if [ $SECRET_MISSING -eq 1 ]; then
  echo ""
  echo -e "${YELLOW}Please create the secrets:${NC}"
  echo "  echo -n 'your-username' | gcloud secrets create last9-username --data-file=- --project=$PROJECT_ID"
  echo "  echo -n 'your-password' | gcloud secrets create last9-password --data-file=- --project=$PROJECT_ID"
  exit 1
fi
echo -e "${GREEN}✓ Secrets found${NC}"

# Step 4: Build Docker image
echo -e "${YELLOW}[4/6] Building Docker image...${NC}"
IMAGE_TAG="gcr.io/$PROJECT_ID/$SERVICE_NAME:$(date +%Y%m%d-%H%M%S)"
docker build -t $IMAGE_TAG -t gcr.io/$PROJECT_ID/$SERVICE_NAME:latest .
echo -e "${GREEN}✓ Docker image built${NC}"

# Step 5: Push to GCR
echo -e "${YELLOW}[5/6] Pushing image to Google Container Registry...${NC}"
docker push $IMAGE_TAG
docker push gcr.io/$PROJECT_ID/$SERVICE_NAME:latest
echo -e "${GREEN}✓ Image pushed${NC}"

# Step 6: Deploy to Cloud Run
echo -e "${YELLOW}[6/6] Deploying to Cloud Run...${NC}"
gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_TAG \
  --region $REGION \
  --platform managed \
  --no-allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 1 \
  --max-instances 1 \
  --timeout 600 \
  --service-account $SERVICE_ACCOUNT \
  --set-env-vars GCP_PROJECT_ID=$PROJECT_ID,REMOTE_WRITE_URL=$REMOTE_WRITE_URL \
  --set-secrets LAST9_USERNAME=last9-username:latest,LAST9_PASSWORD=last9-password:latest \
  --project=$PROJECT_ID

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✓ Deployment completed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "1. Check service status:"
echo "   gcloud run services describe $SERVICE_NAME --region $REGION --project $PROJECT_ID"
echo ""
echo "2. View logs:"
echo "   gcloud run services logs read $SERVICE_NAME --region $REGION --project $PROJECT_ID --limit 50"
echo ""
echo "3. Check metrics in Last9 dashboard"
echo ""
