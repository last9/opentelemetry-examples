#!/bin/bash

# ==============================================================================
# Build and Push Docker Images to ECR
# ==============================================================================
# Builds DBM and CloudWatch collector images and pushes to ECR
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Get AWS account and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-$(aws configure get region)}
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

print_header "Building and Pushing Collector Images"
print_info "Account: $ACCOUNT_ID"
print_info "Region: $REGION"
print_info "Registry: $REGISTRY"

# ==============================================================================
# Create ECR Repositories
# ==============================================================================
print_header "Creating ECR Repositories"

for repo in postgresql-dbm-collector cloudwatch-rds-collector; do
    if aws ecr describe-repositories --repository-names "$repo" &>/dev/null; then
        print_info "Repository exists: $repo"
    else
        print_info "Creating repository: $repo"
        aws ecr create-repository \
            --repository-name "$repo" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        print_success "Created: $repo"
    fi
done

# ==============================================================================
# Login to ECR
# ==============================================================================
print_header "Logging in to ECR"
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY"
print_success "Logged in to ECR"

# ==============================================================================
# Build and Push DBM Collector
# ==============================================================================
print_header "Building DBM Collector"
print_info "Building for linux/amd64 platform (ECS Fargate compatibility)..."
docker build --platform linux/amd64 -f Dockerfile.dbm -t postgresql-dbm-collector:latest .
docker tag postgresql-dbm-collector:latest "$REGISTRY/postgresql-dbm-collector:latest"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
docker tag postgresql-dbm-collector:latest "$REGISTRY/postgresql-dbm-collector:$TIMESTAMP"
print_success "Built DBM Collector"

print_info "Pushing DBM Collector to ECR..."
docker push "$REGISTRY/postgresql-dbm-collector:latest"
docker push "$REGISTRY/postgresql-dbm-collector:$TIMESTAMP"
print_success "Pushed DBM Collector"

# ==============================================================================
# Build and Push CloudWatch Collector
# ==============================================================================
print_header "Building CloudWatch Collector"
print_info "Building for linux/amd64 platform (ECS Fargate compatibility)..."
docker build --platform linux/amd64 -f Dockerfile.cloudwatch -t cloudwatch-rds-collector:latest .
docker tag cloudwatch-rds-collector:latest "$REGISTRY/cloudwatch-rds-collector:latest"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
docker tag cloudwatch-rds-collector:latest "$REGISTRY/cloudwatch-rds-collector:$TIMESTAMP"
print_success "Built CloudWatch Collector"

print_info "Pushing CloudWatch Collector to ECR..."
docker push "$REGISTRY/cloudwatch-rds-collector:latest"
docker push "$REGISTRY/cloudwatch-rds-collector:$TIMESTAMP"
print_success "Pushed CloudWatch Collector"

# ==============================================================================
# Summary
# ==============================================================================
print_header "✓ Complete!"

cat <<EOF
${GREEN}All images built and pushed successfully!${NC}

${BLUE}Images:${NC}
  $REGISTRY/postgresql-dbm-collector:latest
  $REGISTRY/cloudwatch-rds-collector:latest

${BLUE}Update your CloudFormation template with these image URIs or use them in your task definition.${NC}

${BLUE}To use in CloudFormation quick-setup.yaml, update the Image fields in the TaskDefinition.${NC}
EOF
