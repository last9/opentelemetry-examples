#!/bin/bash
# Simple traffic generator that generates rich traces

BASE_URL="${BASE_URL:-http://localhost:3000}"
DURATION="${DURATION:-600}"  # 10 minutes
count=0
end_time=$(($(date +%s) + DURATION))

echo "Generating traffic for ${DURATION} seconds..."

while [[ $(date +%s) -lt $end_time ]]; do
    # Randomly pick endpoint category
    r=$((RANDOM % 100))
    
    if [[ $r -lt 35 ]]; then
        # Payment endpoints (35%) - Rich traces with DB, cache, external calls
        case $((RANDOM % 4)) in
            0) curl -s -o /dev/null "${BASE_URL}/api/v1/payment/status" ;;
            1) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/payment/process" \
                   -H "Content-Type: application/json" \
                   -d "{\"amount\": $((RANDOM % 500 + 10)).99, \"currency\": \"USD\"}" ;;
            2) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/payment/refund" \
                   -H "Content-Type: application/json" \
                   -d "{\"transaction_id\": \"txn_$(openssl rand -hex 8)\", \"amount\": $((RANDOM % 100)).00}" ;;
            3) curl -s -o /dev/null "${BASE_URL}/api/v1/payment/transactions?limit=$((RANDOM % 10 + 5))" ;;
        esac
    elif [[ $r -lt 65 ]]; then
        # Auth endpoints (30%) - With cache and external calls
        case $((RANDOM % 5)) in
            0) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/auth/login" \
                   -H "Content-Type: application/json" \
                   -d "{\"email\": \"user$((RANDOM % 1000))@example.com\"}" ;;
            1) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/auth/logout" \
                   -H "Content-Type: application/json" \
                   -d "{\"session_id\": \"sess_$(openssl rand -hex 16)\"}" ;;
            2) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/auth/refresh" ;;
            3) curl -s -o /dev/null "${BASE_URL}/api/v1/auth/verify" ;;
            4) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/auth/register" \
                   -H "Content-Type: application/json" \
                   -d "{\"email\": \"new$((RANDOM % 10000))@test.com\"}" ;;
        esac
    elif [[ $r -lt 85 ]]; then
        # Internal endpoints (20%)
        case $((RANDOM % 5)) in
            0) curl -s -o /dev/null "${BASE_URL}/api/v1/internal/health" ;;
            1) curl -s -o /dev/null "${BASE_URL}/api/v1/internal/metrics" ;;
            2) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/internal/sync" \
                   -H "Content-Type: application/json" -d '{"type": "full"}' ;;
            3) curl -s -o /dev/null "${BASE_URL}/api/v1/internal/config" ;;
            4) curl -s -o /dev/null -X POST "${BASE_URL}/api/v1/internal/jobs/trigger" \
                   -H "Content-Type: application/json" -d '{"job_type": "cleanup"}' ;;
        esac
    else
        # Public endpoints (15%) - NO service.namespace
        case $((RANDOM % 3)) in
            0) curl -s -o /dev/null "${BASE_URL}/api/v1/public/ping" ;;
            1) curl -s -o /dev/null "${BASE_URL}/api/v1/public/version" ;;
            2) curl -s -o /dev/null "${BASE_URL}/api/v1/public/echo?data=test" ;;
        esac
    fi
    
    ((count++))
    if [[ $((count % 50)) -eq 0 ]]; then
        echo -ne "\rRequests: $count ($(( ($(date +%s) - end_time + DURATION) ))s elapsed)    "
    fi
    
    sleep 0.15
done

echo ""
echo "Traffic generation complete! Total requests: $count"
