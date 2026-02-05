#!/bin/bash
# Traffic Generator for Cloud Run Node.js Express Application
# Generates realistic traffic patterns to test metrics collection

set -e

# Configuration
SERVICE_NAME="${SERVICE_NAME:-cloud-run-nodejs-express}"
REGION="${REGION:-us-central1}"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"

# Get service URL dynamically
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format='value(status.url)' 2>/dev/null)

if [ -z "$SERVICE_URL" ]; then
  echo "ERROR: Could not find Cloud Run service: ${SERVICE_NAME}"
  echo "Set environment variables: SERVICE_NAME, REGION, PROJECT_ID"
  exit 1
fi

DURATION=${1:-300}  # Default: 5 minutes (300 seconds)
REQUESTS_PER_SECOND=${2:-5}  # Default: 5 requests per second

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Cloud Run Traffic Generator ===${NC}"
echo -e "${BLUE}Service URL:${NC} $SERVICE_URL"
echo -e "${BLUE}Duration:${NC} $DURATION seconds"
echo -e "${BLUE}Rate:${NC} $REQUESTS_PER_SECOND requests/second"
echo ""

# Calculate total requests
TOTAL_REQUESTS=$((DURATION * REQUESTS_PER_SECOND))
SLEEP_INTERVAL=$(awk "BEGIN {print 1.0/$REQUESTS_PER_SECOND}")

echo -e "${YELLOW}Starting traffic generation...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Counters
success_count=0
error_count=0
start_time=$(date +%s)

# Trap Ctrl+C
trap 'echo -e "\n${YELLOW}Stopping traffic generation...${NC}"; exit 0' INT

# Traffic generation loop
for i in $(seq 1 $TOTAL_REQUESTS); do
    # Random endpoint selection (weighted)
    rand=$((RANDOM % 100))

    if [ $rand -lt 40 ]; then
        # 40% - Home endpoint
        endpoint="/"
        method="GET"
    elif [ $rand -lt 70 ]; then
        # 30% - Get all users
        endpoint="/users"
        method="GET"
    elif [ $rand -lt 85 ]; then
        # 15% - Get user by ID
        user_id=$((RANDOM % 10 + 1))
        endpoint="/users/$user_id"
        method="GET"
    elif [ $rand -lt 95 ]; then
        # 10% - Create user
        endpoint="/users"
        method="POST"
    else
        # 5% - Error endpoint
        endpoint="/error"
        method="GET"
    fi

    # Make request
    if [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"User$RANDOM\",\"email\":\"user$RANDOM@example.com\"}" \
            "$SERVICE_URL$endpoint" 2>/dev/null || echo "000")
    else
        response=$(curl -s -w "\n%{http_code}" "$SERVICE_URL$endpoint" 2>/dev/null || echo "000")
    fi

    # Extract status code
    status_code=$(echo "$response" | tail -n1)

    # Update counters
    if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 400 ]; then
        ((success_count++))
        status_color=$GREEN
        status_text="✓"
    else
        ((error_count++))
        status_color=$RED
        status_text="✗"
    fi

    # Progress indicator every 10 requests
    if [ $((i % 10)) -eq 0 ]; then
        elapsed=$(($(date +%s) - start_time))
        rate=$(awk "BEGIN {printf \"%.2f\", $i/$elapsed}")
        echo -e "${status_color}${status_text}${NC} [$i/$TOTAL_REQUESTS] ${method} ${endpoint} → ${status_code} | Success: $success_count | Errors: $error_count | Rate: ${rate} req/s"
    fi

    # Sleep to maintain rate
    sleep $SLEEP_INTERVAL
done

# Final statistics
echo ""
echo -e "${GREEN}=== Traffic Generation Complete ===${NC}"
echo -e "${BLUE}Total requests:${NC} $TOTAL_REQUESTS"
echo -e "${GREEN}Successful:${NC} $success_count"
echo -e "${RED}Errors:${NC} $error_count"
echo -e "${BLUE}Success rate:${NC} $(awk "BEGIN {printf \"%.2f%%\", ($success_count*100)/$TOTAL_REQUESTS}")"
echo ""
echo -e "${YELLOW}Check metrics in Last9 dashboard for:${NC}"
echo "  - HTTP request count"
echo "  - Request duration histograms"
echo "  - CPU/Memory utilization"
echo "  - Instance count"
echo ""
