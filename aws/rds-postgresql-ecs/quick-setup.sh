#!/bin/bash

# ==============================================================================
# RDS PostgreSQL Monitoring - Quick Setup Script
# ==============================================================================
# One-command deployment for complete RDS PostgreSQL monitoring
# Deploys OpenTelemetry collectors for RDS monitoring with Last9
#
# PRODUCTION SAFETY:
#   ✅ Does NOT reboot RDS
#   ✅ Does NOT modify RDS parameter groups
#   ✅ Does NOT modify application data
#   ⚠️  OPTIONALLY creates monitoring user (you'll be asked)
#   ✅ Only adds ONE security group ingress rule
#
# See SAFETY_AUDIT.md for complete details before running on production!
# ==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ==============================================================================
# Step 1: Check Prerequisites
# ==============================================================================
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        echo "Visit: https://aws.amazon.com/cli/"
        exit 1
    fi
    print_success "AWS CLI installed"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        echo "Run: aws configure"
        exit 1
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials configured (Account: $ACCOUNT_ID)"

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found (optional, but recommended for better output)"
        echo "Install: brew install jq (macOS) or apt-get install jq (Linux)"
    else
        print_success "jq installed"
    fi
}

# ==============================================================================
# Step 2: Collect Configuration
# ==============================================================================
collect_configuration() {
    print_header "Configuration"

    # Show safety warning
    echo ""
    print_warning "PRODUCTION SAFETY NOTICE"
    echo ""
    echo "This script will:"
    echo "  ✅ Auto-discover RDS endpoint, VPC, subnets (read-only)"
    echo "  ✅ Deploy ECS Fargate collectors"
    echo "  ✅ Add ONE security group ingress rule to RDS"
    echo ""
    echo "  ⚠️  OPTIONAL: Create monitoring database user (otel_monitor)"
    echo "      - Creates read-only monitoring user"
    echo "      - Grants pg_monitor and rds_superuser permissions"
    echo "      - Creates extension pg_stat_statements (may fail if not enabled)"
    echo "      - Creates monitoring schema"
    echo ""
    echo "This script will NOT:"
    echo "  ❌ Reboot your RDS instance"
    echo "  ❌ Modify RDS parameter groups"
    echo "  ❌ Modify or read your application data"
    echo ""
    print_info "See SAFETY_AUDIT.md for complete details"
    echo ""
    echo -n "Continue? [y/N]: "
    read CONTINUE_SETUP
    if [[ ! "$CONTINUE_SETUP" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled"
        exit 0
    fi
    echo ""

    # Check for .env file
    if [ -f ".env" ]; then
        print_info "Found .env file. Loading configuration..."
        source .env
    fi

    # RDS Instance ID
    if [ -z "$RDS_INSTANCE_ID" ]; then
        echo -n "RDS Instance ID: "
        read RDS_INSTANCE_ID
    else
        print_info "RDS Instance ID: $RDS_INSTANCE_ID"
    fi

    # Database Name
    if [ -z "$DATABASE_NAME" ]; then
        echo -n "Database Name [postgres]: "
        read DATABASE_NAME
        DATABASE_NAME=${DATABASE_NAME:-postgres}
    else
        print_info "Database Name: $DATABASE_NAME"
    fi

    # Master Username
    if [ -z "$MASTER_USERNAME" ]; then
        echo -n "RDS Master Username [postgres]: "
        read MASTER_USERNAME
        MASTER_USERNAME=${MASTER_USERNAME:-postgres}
    else
        print_info "Master Username: $MASTER_USERNAME"
    fi

    # Master Password
    if [ -z "$MASTER_PASSWORD" ]; then
        echo -n "RDS Master Password: "
        read -s MASTER_PASSWORD
        echo
    else
        print_info "Master Password: ********"
    fi

    # Last9 OTLP Endpoint
    if [ -z "$LAST9_OTLP_ENDPOINT" ]; then
        echo -n "Last9 OTLP Endpoint (e.g., https://your-endpoint.last9.io): "
        read LAST9_OTLP_ENDPOINT
    else
        print_info "Last9 Endpoint: $LAST9_OTLP_ENDPOINT"
    fi

    # Last9 Username
    if [ -z "$LAST9_USERNAME" ]; then
        echo -n "Last9 Username: "
        read LAST9_USERNAME
    else
        print_info "Last9 Username: $LAST9_USERNAME"
    fi

    # Last9 Password
    if [ -z "$LAST9_PASSWORD" ]; then
        echo -n "Last9 Password/Token: "
        read -s LAST9_PASSWORD
        echo
    else
        print_info "Last9 Password: ********"
    fi

    # Environment
    if [ -z "$ENVIRONMENT" ]; then
        echo -n "Environment [prod/staging/dev] [prod]: "
        read ENVIRONMENT
        ENVIRONMENT=${ENVIRONMENT:-prod}
    else
        print_info "Environment: $ENVIRONMENT"
    fi

    # Stack Name
    STACK_NAME="${STACK_NAME:-rds-postgresql-monitoring-${ENVIRONMENT}}"
    print_info "Stack Name: $STACK_NAME"

    # CREATE MONITORING USER CONFIRMATION
    echo ""
    print_header "Database User Creation (IMPORTANT)"
    echo ""
    echo "The script can automatically create a monitoring database user for you."
    echo ""
    print_warning "This will execute SQL commands on your database:"
    echo "  - CREATE USER otel_monitor"
    echo "  - GRANT pg_monitor, rds_superuser"
    echo "  - CREATE EXTENSION pg_stat_statements (may fail safely)"
    echo "  - CREATE SCHEMA otel_monitor"
    echo ""
    echo "Alternatively, you can:"
    echo "  1. Skip automatic creation (safer for production)"
    echo "  2. Manually run: psql -f scripts/setup-db-user.sql"
    echo ""

    if [ -z "$CREATE_MONITORING_USER" ]; then
        echo -n "Automatically create monitoring user? [y/N]: "
        read CREATE_USER_RESPONSE
        if [[ "$CREATE_USER_RESPONSE" =~ ^[Yy]$ ]]; then
            CREATE_MONITORING_USER="true"
            print_success "Will create monitoring user automatically"
        else
            CREATE_MONITORING_USER="false"
            print_warning "Skipping automatic user creation"
            print_info "After deployment, manually run: psql -h <endpoint> -U $MASTER_USERNAME -f scripts/setup-db-user.sql"
        fi
    else
        if [ "$CREATE_MONITORING_USER" = "true" ]; then
            print_warning "Will create monitoring user automatically (from .env)"
        else
            print_info "Skipping automatic user creation (from .env)"
        fi
    fi
}

# ==============================================================================
# Step 3: Verify RDS Instance
# ==============================================================================
verify_rds_instance() {
    print_header "Verifying RDS Instance"

    print_info "Checking if RDS instance exists: $RDS_INSTANCE_ID"

    if ! aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'DBInstances[0].[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceStatus]' \
        --output text &> /dev/null; then
        print_error "RDS instance not found: $RDS_INSTANCE_ID"
        exit 1
    fi

    RDS_INFO=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'DBInstances[0].[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceStatus,Endpoint.Address]' \
        --output text)

    print_success "Found RDS instance:"
    echo "$RDS_INFO" | awk '{print "  - ID: " $1 "\n  - Engine: " $2 " " $3 "\n  - Status: " $4 "\n  - Endpoint: " $5}'

    # Check parameter group
    print_info "Checking parameter group configuration..."
    PARAM_GROUP=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
        --output text)

    SHARED_PRELOAD=$(aws rds describe-db-parameters \
        --db-parameter-group-name "$PARAM_GROUP" \
        --query "Parameters[?ParameterName=='shared_preload_libraries'].ParameterValue" \
        --output text)

    if [[ "$SHARED_PRELOAD" == *"pg_stat_statements"* ]]; then
        print_success "pg_stat_statements is enabled in parameter group"
    else
        print_warning "pg_stat_statements is NOT enabled in parameter group"
        echo ""
        echo "To enable it, run:"
        echo "  aws rds modify-db-parameter-group \\"
        echo "    --db-parameter-group-name $PARAM_GROUP \\"
        echo "    --parameters \"ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot\""
        echo ""
        echo "  aws rds reboot-db-instance --db-instance-identifier $RDS_INSTANCE_ID"
        echo ""
        echo -n "Continue anyway? [y/N]: "
        read CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# ==============================================================================
# Step 4: Deploy CloudFormation Stack
# ==============================================================================
deploy_stack() {
    print_header "Deploying CloudFormation Stack"

    TEMPLATE_FILE="cloudformation/quick-setup.yaml"

    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "CloudFormation template not found: $TEMPLATE_FILE"
        exit 1
    fi

    print_info "Template: $TEMPLATE_FILE"
    print_info "Stack: $STACK_NAME"

    # Check if stack already exists
    if aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" &> /dev/null; then
        print_warning "Stack already exists: $STACK_NAME"
        echo -n "Update existing stack? [y/N]: "
        read UPDATE
        if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
            ACTION="update-stack"
            print_info "Updating stack..."
        else
            print_info "Skipping deployment"
            return
        fi
    else
        ACTION="create-stack"
        print_info "Creating new stack..."
    fi

    # Deploy stack
    aws cloudformation "$ACTION" \
        --stack-name "$STACK_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
            ParameterKey=RDSInstanceId,ParameterValue="$RDS_INSTANCE_ID" \
            ParameterKey=DatabaseName,ParameterValue="$DATABASE_NAME" \
            ParameterKey=MasterUsername,ParameterValue="$MASTER_USERNAME" \
            ParameterKey=MasterPassword,ParameterValue="$MASTER_PASSWORD" \
            ParameterKey=Last9OtlpEndpoint,ParameterValue="$LAST9_OTLP_ENDPOINT" \
            ParameterKey=Last9Username,ParameterValue="$LAST9_USERNAME" \
            ParameterKey=Last9Password,ParameterValue="$LAST9_PASSWORD" \
            ParameterKey=Last9AuthHeader,ParameterValue="${LAST9_AUTH_HEADER:-}" \
            ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
            ParameterKey=CreateMonitoringUser,ParameterValue="$CREATE_MONITORING_USER" \
            ParameterKey=ExistingDBUsername,ParameterValue="${PG_USERNAME:-}" \
            ParameterKey=ExistingDBPassword,ParameterValue="${PG_PASSWORD:-}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --tags \
            Key=Environment,Value="$ENVIRONMENT" \
            Key=ManagedBy,Value=quick-setup-script

    print_success "Stack deployment initiated"

    # Wait for stack
    print_info "Waiting for stack to complete (this may take 3-5 minutes)..."
    echo ""

    if [ "$ACTION" = "create-stack" ]; then
        aws cloudformation wait stack-create-complete \
            --stack-name "$STACK_NAME" 2>&1
        WAIT_EXIT_CODE=$?
    else
        aws cloudformation wait stack-update-complete \
            --stack-name "$STACK_NAME" 2>&1
        WAIT_EXIT_CODE=$?
    fi

    if [ $WAIT_EXIT_CODE -eq 0 ]; then
        print_success "Stack deployed successfully!"
    else
        print_error "Stack deployment failed"
        echo ""
        echo "Check errors:"
        echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --max-items 10"
        echo ""
        echo "Or check in AWS Console: CloudFormation → $STACK_NAME → Events"
        exit 1
    fi
}

# ==============================================================================
# Step 5: Verify Deployment
# ==============================================================================
verify_deployment() {
    print_header "Verifying Deployment"

    # Get stack outputs
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs' \
        --output json)

    LOG_GROUP=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="LogGroupName") | .OutputValue')
    CLUSTER_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ClusterName") | .OutputValue')
    SERVICE_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ServiceName") | .OutputValue')

    print_success "Stack Outputs:"
    echo "$OUTPUTS" | jq -r '.[] | "  - \(.OutputKey): \(.OutputValue)"'

    # Check ECS service
    print_info "Checking ECS service status..."
    RUNNING_COUNT=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query 'services[0].runningCount' \
        --output text)

    if [ "$RUNNING_COUNT" = "1" ]; then
        print_success "ECS service is running (1 task)"
    else
        print_warning "ECS service tasks: $RUNNING_COUNT (expected 1)"
    fi

    # Check recent logs
    print_info "Checking recent logs (last 5 minutes)..."
    echo ""

    aws logs tail "$LOG_GROUP" --since 5m --format short | head -20

    echo ""
    print_info "To follow logs in real-time:"
    echo "  aws logs tail $LOG_GROUP --follow"
}

# ==============================================================================
# Step 6: Display Next Steps
# ==============================================================================
display_next_steps() {
    print_header "✓ Deployment Complete!"

    cat <<EOF

${GREEN}Your RDS PostgreSQL monitoring is now active!${NC}

${BLUE}What was automated:${NC}
  ✓ Auto-discovered RDS endpoint, VPC, and subnets
  ✓ Created monitoring database user (otel_monitor)
  ✓ Configured security groups automatically
  ✓ Deployed all 3 collectors (OTEL, DBM, CloudWatch)
  ✓ Set up authentication with Last9

${BLUE}Next Steps:${NC}

1. ${YELLOW}Verify metrics in Last9:${NC}
   - Login: https://app.last9.io
   - Search for metrics: postgresql.*, postgresql_dbm_*, rds_*

2. ${YELLOW}Monitor collector logs:${NC}
   aws logs tail $LOG_GROUP --follow

3. ${YELLOW}Check ECS service:${NC}
   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME

4. ${YELLOW}IMPORTANT - Update RDS Parameter Group if needed:${NC}
   If pg_stat_statements was not enabled, run:

   aws rds modify-db-parameter-group \\
     --db-parameter-group-name <your-param-group> \\
     --parameters \\
       "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \\
       "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \\
       "ParameterName=track_io_timing,ParameterValue=1,ApplyMethod=immediate"

   aws rds reboot-db-instance --db-instance-identifier $RDS_INSTANCE_ID

${BLUE}Metrics Available:${NC}
  • 34 PostgreSQL infrastructure metrics (connections, transactions, tables, indexes)
  • 9 Query-level DBM metrics (execution time, I/O, buffer cache)
  • 14 RDS CloudWatch metrics (CPU, memory, IOPS, storage)
  ${GREEN}Total: 57 metrics${NC}

${BLUE}Example Queries in Last9:${NC}
  # CPU Utilization
  rds_cpu_utilization_percent{db_instance_id="$RDS_INSTANCE_ID"}

  # Top 10 slowest queries
  topk(10, postgresql_dbm_query_time_milliseconds_total)

  # Database connections
  postgresql_backends{database="$DATABASE_NAME"}

${BLUE}Troubleshooting:${NC}
  If no metrics appear after 5 minutes:
  1. Check logs: aws logs tail $LOG_GROUP --since 10m
  2. Verify RDS is accessible from collectors
  3. Confirm Last9 credentials are correct
  4. Ensure pg_stat_statements is enabled

${BLUE}Stack Info:${NC}
  Stack Name: $STACK_NAME
  Region: $(aws configure get region)
  Account: $ACCOUNT_ID

${BLUE}To delete everything:${NC}
  aws cloudformation delete-stack --stack-name $STACK_NAME

EOF
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    print_header "RDS PostgreSQL Monitoring - Quick Setup"

    echo "This script will deploy OpenTelemetry collectors to monitor your RDS instance"
    echo "and send metrics to Last9."
    echo ""

    check_prerequisites
    collect_configuration
    verify_rds_instance
    deploy_stack
    verify_deployment
    display_next_steps
}

# Run main function
main
