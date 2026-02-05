#!/bin/bash

# Chaos Traffic Generator for Rails API with OpenTelemetry
# Generates realistic traffic across all namespaces (payment, auth, internal)

set -e

BASE_URL="${BASE_URL:-http://localhost:3000}"
DURATION="${DURATION:-300}"  # Default 5 minutes
CONCURRENCY="${CONCURRENCY:-5}"
REQUEST_DELAY="${REQUEST_DELAY:-0.1}"  # Delay between requests in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_REQUESTS=0
SUCCESSFUL_REQUESTS=0
FAILED_REQUESTS=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Payment namespace endpoints
call_payment_status() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/payment/status"
}

call_payment_process() {
    local amount=$(echo "scale=2; $RANDOM/100" | bc)
    local currencies=("USD" "EUR" "GBP" "JPY")
    local currency=${currencies[$RANDOM % ${#currencies[@]}]}
    local methods=("card" "bank_transfer" "wallet")
    local method=${methods[$RANDOM % ${#methods[@]}]}

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/payment/process" \
        -H "Content-Type: application/json" \
        -d "{\"amount\": ${amount}, \"currency\": \"${currency}\", \"method\": \"${method}\"}"
}

call_payment_refund() {
    local amount=$(echo "scale=2; $RANDOM/100" | bc)
    local txn_id="txn_$(openssl rand -hex 12)"

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/payment/refund" \
        -H "Content-Type: application/json" \
        -d "{\"transaction_id\": \"${txn_id}\", \"amount\": ${amount}}"
}

call_payment_transactions() {
    local limit=$((RANDOM % 20 + 5))
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/payment/transactions?limit=${limit}"
}

# Auth namespace endpoints
call_auth_login() {
    local user_id=$((RANDOM % 1000))
    local domains=("example.com" "test.org" "demo.io" "company.net")
    local domain=${domains[$RANDOM % ${#domains[@]}]}

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"user${user_id}@${domain}\", \"password\": \"password123\"}"
}

call_auth_logout() {
    local session_id="sess_$(openssl rand -hex 16)"
    local types=("user_initiated" "timeout" "admin_forced")
    local type=${types[$RANDOM % ${#types[@]}]}

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/auth/logout" \
        -H "Content-Type: application/json" \
        -d "{\"session_id\": \"${session_id}\", \"type\": \"${type}\"}"
}

call_auth_refresh() {
    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/auth/refresh" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer tok_$(openssl rand -hex 32)"
}

call_auth_verify() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/auth/verify" \
        -H "Authorization: Bearer tok_$(openssl rand -hex 32)"
}

call_auth_register() {
    local user_id=$((RANDOM % 100000))
    local domains=("gmail.com" "yahoo.com" "outlook.com" "proton.me")
    local domain=${domains[$RANDOM % ${#domains[@]}]}

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"newuser${user_id}@${domain}\", \"password\": \"securepass123\"}"
}

# Internal namespace endpoints
call_internal_health() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/internal/health"
}

call_internal_metrics() {
    local formats=("json" "prometheus" "statsd")
    local format=${formats[$RANDOM % ${#formats[@]}]}
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/internal/metrics?format=${format}"
}

call_internal_sync() {
    local types=("full" "incremental" "delta")
    local type=${types[$RANDOM % ${#types[@]}]}
    local targets=("all" "users" "orders" "inventory")
    local target=${targets[$RANDOM % ${#targets[@]}]}

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/internal/sync" \
        -H "Content-Type: application/json" \
        -d "{\"type\": \"${type}\", \"target\": \"${target}\"}"
}

call_internal_cache_invalidate() {
    local keys=("user:*" "session:*" "product:*" "order:*")
    local key=${keys[$RANDOM % ${#keys[@]}]}
    local pattern=$((RANDOM % 2))

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/internal/cache/invalidate" \
        -H "Content-Type: application/json" \
        -d "{\"key\": \"${key}\", \"pattern\": ${pattern}}"
}

call_internal_config() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/internal/config"
}

call_internal_trigger_job() {
    local job_types=("cleanup" "report" "notification" "sync" "backup")
    local job_type=${job_types[$RANDOM % ${#job_types[@]}]}
    local priorities=("low" "normal" "high" "critical")
    local priority=${priorities[$RANDOM % ${#priorities[@]}]}

    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/internal/jobs/trigger" \
        -H "Content-Type: application/json" \
        -d "{\"job_type\": \"${job_type}\", \"priority\": \"${priority}\"}"
}

# Public endpoints (NO service.namespace)
call_public_ping() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/public/ping"
}

call_public_version() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/public/version"
}

call_public_echo() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/public/echo?test=value"
}

# Users namespace endpoints
call_users_index() {
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/users"
}

call_users_show() {
    local user_id=$((RANDOM % 100 + 1))
    curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/users/${user_id}"
}

call_users_create() {
    local user_id=$((RANDOM % 100000))
    curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/users" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"User ${user_id}\", \"email\": \"user${user_id}@example.com\"}"
}

# Array of all endpoint functions with weights (more common operations have higher weight)
declare -a ENDPOINTS=(
    # Payment (weight: 30%)
    "call_payment_status"
    "call_payment_status"
    "call_payment_process"
    "call_payment_process"
    "call_payment_process"
    "call_payment_process"
    "call_payment_refund"
    "call_payment_refund"
    "call_payment_transactions"

    # Auth (weight: 35%)
    "call_auth_login"
    "call_auth_login"
    "call_auth_login"
    "call_auth_login"
    "call_auth_verify"
    "call_auth_verify"
    "call_auth_verify"
    "call_auth_refresh"
    "call_auth_refresh"
    "call_auth_logout"
    "call_auth_register"

    # Internal (weight: 30%)
    "call_internal_health"
    "call_internal_health"
    "call_internal_metrics"
    "call_internal_metrics"
    "call_internal_config"
    "call_internal_config"
    "call_internal_sync"
    "call_internal_cache_invalidate"
    "call_internal_trigger_job"

    # Users (weight: 5%)
    "call_users_show"

    # Public - NO service.namespace (weight: 10%)
    "call_public_ping"
    "call_public_ping"
    "call_public_version"
    "call_public_echo"
)

make_request() {
    local endpoint=${ENDPOINTS[$RANDOM % ${#ENDPOINTS[@]}]}
    local status_code

    status_code=$($endpoint 2>/dev/null || echo "000")

    ((TOTAL_REQUESTS++))

    if [[ "$status_code" =~ ^2[0-9][0-9]$ ]]; then
        ((SUCCESSFUL_REQUESTS++))
        echo -ne "\r${GREEN}✓${NC} [${TOTAL_REQUESTS}] ${endpoint##call_} -> ${status_code}     "
    elif [[ "$status_code" =~ ^4[0-9][0-9]$ ]]; then
        ((SUCCESSFUL_REQUESTS++))  # 4xx are expected for auth failures, etc.
        echo -ne "\r${YELLOW}⚠${NC} [${TOTAL_REQUESTS}] ${endpoint##call_} -> ${status_code}     "
    else
        ((FAILED_REQUESTS++))
        echo -ne "\r${RED}✗${NC} [${TOTAL_REQUESTS}] ${endpoint##call_} -> ${status_code}     "
    fi
}

run_traffic() {
    local worker_id=$1
    local end_time=$(($(date +%s) + DURATION))

    while [[ $(date +%s) -lt $end_time ]]; do
        make_request
        sleep "$REQUEST_DELAY"
    done
}

print_banner() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}           ${GREEN}Chaos Traffic Generator for Rails API${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                  ${YELLOW}OpenTelemetry Edition${NC}                       ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_config() {
    log_info "Configuration:"
    echo "  • Base URL:     ${BASE_URL}"
    echo "  • Duration:     ${DURATION}s"
    echo "  • Concurrency:  ${CONCURRENCY}"
    echo "  • Request Delay: ${REQUEST_DELAY}s"
    echo ""
    log_info "Namespaces being tested:"
    echo "  • ${GREEN}payment${NC}  - /api/v1/payment/*"
    echo "  • ${GREEN}auth${NC}     - /api/v1/auth/*"
    echo "  • ${GREEN}internal${NC} - /api/v1/internal/*"
    echo "  • ${GREEN}users${NC}    - /api/v1/users/*"
    echo ""
}

print_summary() {
    echo ""
    echo ""
    log_info "Traffic Generation Complete!"
    echo ""
    echo -e "  ${GREEN}Total Requests:${NC}      ${TOTAL_REQUESTS}"
    echo -e "  ${GREEN}Successful:${NC}          ${SUCCESSFUL_REQUESTS}"
    echo -e "  ${RED}Failed:${NC}              ${FAILED_REQUESTS}"

    if [[ $TOTAL_REQUESTS -gt 0 ]]; then
        local success_rate=$((SUCCESSFUL_REQUESTS * 100 / TOTAL_REQUESTS))
        echo -e "  ${BLUE}Success Rate:${NC}        ${success_rate}%"
    fi
    echo ""
}

check_server() {
    log_info "Checking if server is running at ${BASE_URL}..."

    if curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/v1/internal/health" | grep -q "200\|503"; then
        log_success "Server is running!"
        return 0
    else
        log_error "Server is not responding at ${BASE_URL}"
        log_info "Please start the server first with: bundle exec rails s"
        exit 1
    fi
}

main() {
    print_banner
    print_config
    check_server

    log_info "Starting traffic generation for ${DURATION} seconds..."
    echo ""

    trap print_summary EXIT

    # Run traffic generators
    for i in $(seq 1 $CONCURRENCY); do
        run_traffic $i &
    done

    wait
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            BASE_URL="$2"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -c|--concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        -r|--rate)
            REQUEST_DELAY="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -u, --url URL         Base URL (default: http://localhost:3000)"
            echo "  -d, --duration SECS   Duration in seconds (default: 300)"
            echo "  -c, --concurrency N   Number of concurrent workers (default: 5)"
            echo "  -r, --rate SECS       Delay between requests (default: 0.1)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  BASE_URL              Same as -u"
            echo "  DURATION              Same as -d"
            echo "  CONCURRENCY           Same as -c"
            echo "  REQUEST_DELAY         Same as -r"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
