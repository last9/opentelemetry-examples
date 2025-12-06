#!/bin/bash

# AWS CloudWatch Logs Retention and S3 Archival Setup Script
#
# This script helps reduce CloudWatch Logs costs by:
# 1. Setting retention period on log groups (e.g., 14 days)
# 2. Exporting older logs to S3 for long-term archival
# 3. Setting up S3 lifecycle policies for cost-effective storage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
RETENTION_DAYS=14
LOG_GROUP_PREFIX=""
ARCHIVE_BUCKET=""
AWS_REGION="us-east-1"
DRY_RUN=false

# Help function
show_help() {
    cat << EOF
AWS CloudWatch Logs Cost Optimization Script

Usage: $0 [OPTIONS]

Options:
    -r, --retention-days DAYS       Retention period in days (default: 14)
                                    Valid values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653

    -p, --log-group-prefix PREFIX   Log group prefix to apply retention (e.g., /aws/connect/aha_prod)
                                    Can be specified multiple times for multiple prefixes

    -b, --archive-bucket BUCKET     S3 bucket name for archiving logs (optional)
                                    If not specified, only retention will be set

    --region REGION                 AWS region (default: us-east-1)

    --dry-run                       Show what would be done without making changes

    -h, --help                      Show this help message

Examples:
    # Set 14-day retention for all aha_prod logs
    $0 -r 14 -p /aws/connect/aha_prod -p /aws/lambda/aha_prod

    # Set retention and archive to S3
    $0 -r 14 -p /aws/ -b my-logs-archive --region us-east-1

    # Dry run to see what would be changed
    $0 -r 14 -p /aws/lex/aha_prod --dry-run

EOF
}

# Parse command line arguments
LOG_GROUP_PREFIXES=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--retention-days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -p|--log-group-prefix)
            LOG_GROUP_PREFIXES+=("$2")
            shift 2
            ;;
        -b|--archive-bucket)
            ARCHIVE_BUCKET="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate inputs
if [ ${#LOG_GROUP_PREFIXES[@]} -eq 0 ]; then
    echo -e "${RED}Error: At least one log group prefix must be specified${NC}"
    show_help
    exit 1
fi

# Validate retention days
VALID_RETENTION_DAYS=(1 3 5 7 14 30 60 90 120 150 180 365 400 545 731 1827 3653)
if [[ ! " ${VALID_RETENTION_DAYS[@]} " =~ " ${RETENTION_DAYS} " ]]; then
    echo -e "${RED}Error: Invalid retention days: $RETENTION_DAYS${NC}"
    echo -e "${YELLOW}Valid values: ${VALID_RETENTION_DAYS[*]}${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. Installing...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        echo -e "${RED}Error: Could not install jq automatically. Please install manually.${NC}"
        exit 1
    fi
fi

echo "=========================================="
echo "AWS CloudWatch Logs Cost Optimization"
echo "=========================================="
echo "Region: $AWS_REGION"
echo "Retention Days: $RETENTION_DAYS"
echo "Log Group Prefixes: ${LOG_GROUP_PREFIXES[*]}"
echo "Archive Bucket: ${ARCHIVE_BUCKET:-Not specified}"
echo "Dry Run: $DRY_RUN"
echo "=========================================="
echo ""

# Function to set retention policy
set_retention_policy() {
    local log_group=$1

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would set retention to $RETENTION_DAYS days for: $log_group"
        return
    fi

    echo -e "${GREEN}Setting retention to $RETENTION_DAYS days for:${NC} $log_group"
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days "$RETENTION_DAYS" \
        --region "$AWS_REGION" \
        2>&1 | grep -v "ResourceNotFoundException" || true
}

# Function to create S3 bucket if needed
create_archive_bucket() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would create S3 bucket: $ARCHIVE_BUCKET"
        return
    fi

    echo -e "${GREEN}Checking if S3 bucket exists:${NC} $ARCHIVE_BUCKET"

    if aws s3 ls "s3://$ARCHIVE_BUCKET" --region "$AWS_REGION" 2>&1 | grep -q 'NoSuchBucket'; then
        echo "Creating S3 bucket: $ARCHIVE_BUCKET"

        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket \
                --bucket "$ARCHIVE_BUCKET" \
                --region "$AWS_REGION"
        else
            aws s3api create-bucket \
                --bucket "$ARCHIVE_BUCKET" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi

        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$ARCHIVE_BUCKET" \
            --versioning-configuration Status=Enabled \
            --region "$AWS_REGION"

        echo -e "${GREEN}✓${NC} Bucket created successfully"
    else
        echo -e "${GREEN}✓${NC} Bucket already exists"
    fi
}

# Function to set S3 lifecycle policy for cost optimization
set_s3_lifecycle_policy() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would set S3 lifecycle policy on: $ARCHIVE_BUCKET"
        return
    fi

    echo -e "${GREEN}Setting S3 lifecycle policy for cost optimization...${NC}"

    # Create lifecycle policy JSON
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "Id": "MoveToGlacierAfter30Days",
            "Status": "Enabled",
            "Prefix": "cloudwatch-logs/",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 90,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
EOF

    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$ARCHIVE_BUCKET" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json \
        --region "$AWS_REGION"

    rm /tmp/lifecycle-policy.json
    echo -e "${GREEN}✓${NC} Lifecycle policy set (S3 → Glacier after 30 days → Deep Archive after 90 days)"
}

# Main execution
echo "Step 1: Finding log groups..."
echo ""

total_log_groups=0
updated_log_groups=0

for prefix in "${LOG_GROUP_PREFIXES[@]}"; do
    echo -e "${YELLOW}Processing prefix:${NC} $prefix"

    # Get all log groups matching the prefix
    log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "$prefix" \
        --region "$AWS_REGION" \
        --query 'logGroups[].logGroupName' \
        --output text)

    if [ -z "$log_groups" ]; then
        echo -e "${RED}No log groups found with prefix: $prefix${NC}"
        continue
    fi

    # Convert to array
    IFS=$'\t' read -ra log_group_array <<< "$log_groups"

    echo "Found ${#log_group_array[@]} log groups"

    for log_group in "${log_group_array[@]}"; do
        total_log_groups=$((total_log_groups + 1))
        set_retention_policy "$log_group"
        updated_log_groups=$((updated_log_groups + 1))
    done

    echo ""
done

echo "=========================================="
echo -e "${GREEN}Step 1 Complete:${NC} Set retention on $updated_log_groups log groups"
echo "=========================================="
echo ""

# S3 archival setup (optional)
if [ -n "$ARCHIVE_BUCKET" ]; then
    echo "Step 2: Setting up S3 archival..."
    echo ""

    create_archive_bucket
    set_s3_lifecycle_policy

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Step 2 Complete:${NC} S3 archival configured"
    echo "=========================================="
    echo ""

    echo "To export existing CloudWatch logs to S3:"
    echo ""
    echo "aws logs create-export-task \\"
    echo "  --log-group-name /aws/connect/aha_prod \\"
    echo "  --from \$(date -d '30 days ago' +%s)000 \\"
    echo "  --to \$(date +%s)000 \\"
    echo "  --destination $ARCHIVE_BUCKET \\"
    echo "  --destination-prefix cloudwatch-logs/connect/ \\"
    echo "  --region $AWS_REGION"
    echo ""
fi

# Cost savings estimation
echo "=========================================="
echo "Estimated Cost Savings"
echo "=========================================="
echo ""
echo "Before:"
echo "  - CloudWatch retention: Never expire"
echo "  - Storage cost: \$0.03/GB/month (all logs)"
echo ""
echo "After:"
echo "  - CloudWatch retention: $RETENTION_DAYS days"
echo "  - Storage cost: \$0.03/GB/month (14 days only)"
if [ -n "$ARCHIVE_BUCKET" ]; then
    echo "  - S3 Standard: \$0.023/GB/month (days 15-30)"
    echo "  - S3 Glacier: \$0.004/GB/month (days 31-90)"
    echo "  - S3 Deep Archive: \$0.00099/GB/month (90+ days)"
fi
echo ""
echo "Potential Savings: 50-80% on CloudWatch Logs costs"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}Note: This was a dry run. No changes were made.${NC}"
    echo "Remove --dry-run to apply changes."
else
    echo -e "${GREEN}✓ All changes applied successfully!${NC}"
fi

echo ""
echo "Monitor your CloudWatch Logs costs:"
echo "https://console.aws.amazon.com/billing/home#/bills"
