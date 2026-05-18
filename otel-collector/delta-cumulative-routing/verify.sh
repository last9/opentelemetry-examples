#!/usr/bin/env bash
# Queries VictoriaMetrics to verify correct routing of delta vs cumulative metrics.
# Run after: docker compose up -d && sleep 30

VM="http://localhost:8428"

query() {
  local label=$1
  local expr=$2
  echo ""
  echo "=== $label ==="
  curl -sg "${VM}/api/v1/query" --data-urlencode "query=${expr}" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('data', {}).get('result', [])
if not results:
    print('  (no data)')
for r in results:
    print('  labels:', r['metric'])
    print('  value: ', r['value'][1])
"
}

echo "========================================"
echo " Verifying delta vs cumulative routing  "
echo "========================================"

# 1. Delta series: should have collector_id label (one per pod)
query "Delta counter — expect 2 series, one per collector_id" \
  'demo_requests_delta_total'

# 2. Cumulative series: should have NO collector_id label (one series total)
query "Cumulative counter — expect 1 series, no collector_id" \
  'demo_requests_cumulative_total'

# 3. Correct delta total: sum across collector_ids
query "Delta total (correct) — sum without(collector_id)" \
  'sum without(collector_id)(demo_requests_delta_total)'

# 4. Naive delta total WITHOUT dedup — shows overcount risk if collector_id absent
query "Delta rate per pod (each pod's partial view)" \
  'rate(demo_requests_delta_total[1m])'

# 5. Combined delta rate — sum across pods
query "Delta rate total (correct) — sum of per-pod rates" \
  'sum without(collector_id)(rate(demo_requests_delta_total[1m]))'

# 6. Cumulative rate — works directly, no dedup needed
query "Cumulative rate (works natively) — rate(cumulative[1m])" \
  'rate(demo_requests_cumulative_total[1m])'

echo ""
echo "========================================"
echo " Series count sanity check              "
echo "========================================"

count() {
  local label=$1
  local expr=$2
  local n
  n=$(curl -sg "${VM}/api/v1/query" --data-urlencode "query=count(${expr})" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else 0)")
  echo "  $label: $n series"
}

count "demo_requests_delta_total (expect 2, one per pod)" "demo_requests_delta_total"
count "demo_requests_cumulative_total (expect 1)"         "demo_requests_cumulative_total"
