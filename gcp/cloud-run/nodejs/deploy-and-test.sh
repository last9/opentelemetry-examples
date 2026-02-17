#!/bin/bash
#
# End-to-end deployment and testing for GCP Cloud Run with custom trace propagator
# This script deploys functions and services, then tests trace context propagation
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (override with environment variables)
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project)}"
REGION="${REGION:-us-central1}"
OTLP_ENDPOINT="${OTLP_ENDPOINT:-}"
OTLP_AUTH="${OTLP_AUTH:-}"

# Secret name for Last9 credentials
SECRET_NAME="last9-auth-header"

# Service/Function names
FUNCTION_NAME="${FUNCTION_NAME:-otel-test-function}"
SERVICE_NAME="${SERVICE_NAME:-otel-test-service}"

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

# Check prerequisites
check_prerequisites() {
  print_header "Checking Prerequisites"

  # Check gcloud
  if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI not found. Install from https://cloud.google.com/sdk/docs/install"
    exit 1
  fi
  print_success "gcloud CLI found"

  # Check authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    print_error "Not authenticated with gcloud. Run: gcloud auth login"
    exit 1
  fi
  print_success "Authenticated with gcloud"

  # Check project
  if [ -z "$PROJECT_ID" ]; then
    print_error "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
  fi
  print_success "Using project: $PROJECT_ID"

  # Check APIs
  print_info "Checking required APIs..."
  REQUIRED_APIS=(
    "cloudfunctions.googleapis.com"
    "run.googleapis.com"
    "cloudbuild.googleapis.com"
    "secretmanager.googleapis.com"
  )

  for api in "${REQUIRED_APIS[@]}"; do
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" 2>/dev/null | grep -q "$api"; then
      print_success "API enabled: $api"
    else
      print_warning "API not enabled: $api"
      print_info "Enabling $api..."
      gcloud services enable "$api" --project="$PROJECT_ID"
      print_success "Enabled: $api"
    fi
  done
}

# Create/update secret for Last9 credentials
setup_secret() {
  print_header "Setting Up Last9 Credentials Secret"

  if [ -z "$OTLP_ENDPOINT" ] || [ -z "$OTLP_AUTH" ]; then
    print_warning "OTLP_ENDPOINT or OTLP_AUTH not set"
    print_info "You'll need to set these before deploying:"
    echo "  export OTLP_ENDPOINT='https://otlp.last9.io'"
    echo "  export OTLP_AUTH='Authorization=Basic YOUR_BASE64_CREDENTIALS'"
    return
  fi

  # Check if secret exists
  if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &> /dev/null; then
    print_info "Secret '$SECRET_NAME' already exists. Updating..."
    echo -n "$OTLP_AUTH" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
    print_success "Updated secret version"
  else
    print_info "Creating secret '$SECRET_NAME'..."
    echo -n "$OTLP_AUTH" | gcloud secrets create "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
    print_success "Created secret"
  fi

  # Grant access to default compute service account
  COMPUTE_SA="${PROJECT_ID}@appspot.gserviceaccount.com"
  print_info "Granting access to service account: $COMPUTE_SA"
  gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID" \
    --quiet
  print_success "Access granted"
}

# Deploy the Cloud Run Function with custom propagator
deploy_function() {
  print_header "Deploying Cloud Run Function: $FUNCTION_NAME"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR/functions"

  print_info "Deploying function with custom trace propagator..."
  gcloud functions deploy "$FUNCTION_NAME" \
    --gen2 \
    --runtime=nodejs20 \
    --region="$REGION" \
    --source=. \
    --entry-point=helloHttp \
    --trigger-http \
    --allow-unauthenticated \
    --memory=256Mi \
    --timeout=60s \
    --set-env-vars="OTEL_SERVICE_NAME=${FUNCTION_NAME}" \
    --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=${OTLP_ENDPOINT}" \
    --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=${SECRET_NAME}:latest" \
    --project="$PROJECT_ID"

  # Get function URL
  FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)')

  cd "$SCRIPT_DIR"

  print_success "Function deployed: $FUNCTION_URL"
  echo "$FUNCTION_URL" > "$SCRIPT_DIR/.function_url"
}

# Deploy the Cloud Run Service with custom propagator
deploy_service() {
  print_header "Deploying Cloud Run Service: $SERVICE_NAME"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Load function URL
  if [ -f "$SCRIPT_DIR/.function_url" ]; then
    FUNCTION_URL=$(cat "$SCRIPT_DIR/.function_url")
  fi

  cd "$SCRIPT_DIR/service"

  print_info "Building and deploying service with custom trace propagator..."
  gcloud run deploy "$SERVICE_NAME" \
    --source=. \
    --platform=managed \
    --region="$REGION" \
    --allow-unauthenticated \
    --memory=256Mi \
    --timeout=60s \
    --set-env-vars="OTEL_SERVICE_NAME=${SERVICE_NAME}" \
    --set-env-vars="OTEL_EXPORTER_OTLP_ENDPOINT=${OTLP_ENDPOINT}" \
    --set-env-vars="FUNCTION_URL=${FUNCTION_URL}" \
    --set-secrets="OTEL_EXPORTER_OTLP_HEADERS=${SECRET_NAME}:latest" \
    --project="$PROJECT_ID"

  # Get service URL
  SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
    --platform=managed \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(status.url)')

  cd "$SCRIPT_DIR"

  print_success "Service deployed: $SERVICE_URL"
  echo "$SERVICE_URL" > "$SCRIPT_DIR/.service_url"
}

# Test trace propagation
test_traces() {
  print_header "Testing Trace Propagation"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Load URLs
  if [ -f "$SCRIPT_DIR/.function_url" ]; then
    FUNCTION_URL=$(cat "$SCRIPT_DIR/.function_url")
  fi
  if [ -f "$SCRIPT_DIR/.service_url" ]; then
    SERVICE_URL=$(cat "$SCRIPT_DIR/.service_url")
  fi

  if [ -z "$FUNCTION_URL" ] || [ -z "$SERVICE_URL" ]; then
    print_error "URLs not found. Deploy services first."
    exit 1
  fi

  print_info "Function URL: $FUNCTION_URL"
  print_info "Service URL: $SERVICE_URL"

  echo ""
  print_info "Test 1: Direct function call"
  echo "This should create a single trace with the function span as root"
  echo "Command: curl \"$FUNCTION_URL/?name=DirectTest\""
  curl -s "$FUNCTION_URL/?name=DirectTest" | jq '.' || curl -s "$FUNCTION_URL/?name=DirectTest"
  sleep 2

  echo ""
  print_info "Test 2: Service -> Function chain (tests custom propagator)"
  echo "This should create a trace with proper parent-child relationship:"
  echo "  Root: Service span (GET /chain)"
  echo "  └─ Child: HTTP client span (service calling function)"
  echo "     └─ Child: Function span (GET helloHttp)"
  echo "Command: curl \"$SERVICE_URL/chain?name=ChainTest\""
  RESPONSE=$(curl -s "$SERVICE_URL/chain?name=ChainTest")
  echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"

  # Extract traceId if possible
  TRACE_ID=$(echo "$RESPONSE" | jq -r '.traceId // empty' 2>/dev/null)
  if [ -n "$TRACE_ID" ]; then
    print_success "TraceId: $TRACE_ID"
  fi

  sleep 2

  echo ""
  print_info "Test 3: Multiple requests to generate traffic"
  for i in {1..5}; do
    echo "  Request $i/5..."
    curl -s "$SERVICE_URL/chain?name=LoadTest$i" > /dev/null
    sleep 0.5
  done
  print_success "Generated 5 test requests"

  echo ""
  print_header "Verification Steps"
  echo ""
  echo "1. Go to Last9: https://app.last9.io"
  echo ""
  echo "2. Navigate to APM > Traces"
  echo ""
  echo "3. Filter by service: $SERVICE_NAME or $FUNCTION_NAME"
  echo ""
  echo "4. Look for traces from the last few minutes"
  echo ""
  echo "5. Check for trace with TraceId: $TRACE_ID (if captured)"
  echo ""
  echo "6. Verify the span hierarchy shows:"
  echo "   ${GREEN}✓${NC} Service span as parent"
  echo "   ${GREEN}✓${NC} HTTP client span as child of service"
  echo "   ${GREEN}✓${NC} Function span as child of HTTP client"
  echo "   ${GREEN}✓${NC} All spans have the SAME TraceId"
  echo "   ${GREEN}✓${NC} ParentSpanIds reference spans that EXIST in the trace"
  echo ""
  echo "7. Check logs for custom propagator messages:"
  echo "   Look for: '[CloudRunPropagator] Injected backup header'"
  echo "   Look for: '[CloudRunPropagator] Found backup header'"
  echo ""

  # Provide gcloud logs commands
  print_header "View Logs"
  echo ""
  echo "Function logs (look for propagator messages):"
  echo "  gcloud functions logs read $FUNCTION_NAME --gen2 --region=$REGION --limit=50"
  echo ""
  echo "Service logs (look for propagator messages):"
  echo "  gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME\" --limit=50 --format=json"
  echo ""
}

# View logs
view_logs() {
  print_header "Recent Logs"

  echo ""
  print_info "Function logs (last 20 lines):"
  gcloud functions logs read "$FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --limit=20 \
    --project="$PROJECT_ID" 2>/dev/null || print_warning "No function logs available yet"

  echo ""
  print_info "Service logs (last 20 lines):"
  gcloud logging read \
    "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" \
    --limit=20 \
    --project="$PROJECT_ID" \
    --format="table(timestamp,severity,jsonPayload.message,jsonPayload.function)" 2>/dev/null || print_warning "No service logs available yet"
}

# Cleanup
cleanup() {
  print_header "Cleanup Resources"

  read -p "Delete function $FUNCTION_NAME? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    gcloud functions delete "$FUNCTION_NAME" --gen2 --region="$REGION" --project="$PROJECT_ID" --quiet
    print_success "Function deleted"
  fi

  read -p "Delete service $SERVICE_NAME? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    gcloud run services delete "$SERVICE_NAME" --platform=managed --region="$REGION" --project="$PROJECT_ID" --quiet
    print_success "Service deleted"
  fi

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  rm -f "$SCRIPT_DIR/.function_url" "$SCRIPT_DIR/.service_url"
}

# Main menu
main() {
  if [ $# -eq 0 ]; then
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all         - Run full deployment and testing"
    echo "  check       - Check prerequisites only"
    echo "  secret      - Setup Last9 credentials secret"
    echo "  function    - Deploy function only"
    echo "  service     - Deploy service only"
    echo "  test        - Run trace propagation tests"
    echo "  logs        - View recent logs"
    echo "  cleanup     - Delete deployed resources"
    echo ""
    echo "Environment variables:"
    echo "  GOOGLE_CLOUD_PROJECT  - GCP project ID"
    echo "  REGION                - GCP region (default: us-central1)"
    echo "  OTLP_ENDPOINT         - Last9 OTLP endpoint"
    echo "  OTLP_AUTH             - Last9 auth header (Authorization=Basic ...)"
    echo "  FUNCTION_NAME         - Function name (default: otel-test-function)"
    echo "  SERVICE_NAME          - Service name (default: otel-test-service)"
    echo ""
    echo "Example:"
    echo "  export OTLP_ENDPOINT='https://otlp.last9.io'"
    echo "  export OTLP_AUTH='Authorization=Basic YOUR_BASE64_CREDENTIALS'"
    echo "  $0 all"
    exit 1
  fi

  case "$1" in
    all)
      check_prerequisites
      setup_secret
      deploy_function
      deploy_service
      test_traces
      ;;
    check)
      check_prerequisites
      ;;
    secret)
      setup_secret
      ;;
    function)
      check_prerequisites
      deploy_function
      ;;
    service)
      check_prerequisites
      deploy_service
      ;;
    test)
      test_traces
      ;;
    logs)
      view_logs
      ;;
    cleanup)
      cleanup
      ;;
    *)
      echo "Unknown command: $1"
      exit 1
      ;;
  esac
}

main "$@"
