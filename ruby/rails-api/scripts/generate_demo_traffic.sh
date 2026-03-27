#!/usr/bin/env bash
# Generate demo traffic for rails-otel-context Trilogy adapter demo
# Hits various endpoints to produce rich OTel spans with source location attributes

BASE_URL="${1:-http://localhost:3000}"
ROUNDS="${2:-50}"

echo "Generating demo traffic: $ROUNDS rounds against $BASE_URL"
echo "---"

for i in $(seq 1 "$ROUNDS"); do
  echo "Round $i/$ROUNDS"

  # Process payments (creates DB writes, external API calls, cache ops)
  for amount in 49.99 129.50 299.00 15.75 500.00; do
    method=$(echo "card wallet bank_transfer" | tr ' ' '\n' | shuf -n1)
    user_id="usr_demo_$(( (RANDOM % 20) + 1 ))"
    curl -s -X POST "$BASE_URL/api/v1/payment/process" \
      -d "amount=$amount&currency=USD&method=$method&user_id=$user_id" > /dev/null &
  done
  wait

  # List transactions (DB reads, cache reads)
  for user in usr_demo_1 usr_demo_5 usr_demo_10 usr_demo_15; do
    curl -s "$BASE_URL/api/v1/payment/transactions?user_id=$user&limit=5" > /dev/null &
  done
  wait

  # Payment status checks (cache hits/misses)
  for _ in 1 2 3; do
    curl -s "$BASE_URL/api/v1/payment/status" > /dev/null &
  done
  wait

  # Refunds (DB writes + reads + cache invalidation)
  txn_id="txn_$(openssl rand -hex 12)"
  curl -s -X POST "$BASE_URL/api/v1/payment/refund" \
    -d "transaction_id=$txn_id&amount=25.00" > /dev/null

  # User CRUD operations
  curl -s "$BASE_URL/api/v1/users" > /dev/null
  curl -s "$BASE_URL/api/v1/users/42" > /dev/null
  curl -s -X POST "$BASE_URL/api/v1/users" -d "name=Demo&email=demo@test.com" > /dev/null

  # Health check
  curl -s "$BASE_URL/api/v1/internal/health" > /dev/null

  # Small delay between rounds to spread traces
  sleep 0.5
done

echo "---"
echo "Done! Generated traffic across $ROUNDS rounds."
echo "Check Last9 for service: rails-trilogy-otel-demo"
