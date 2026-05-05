#!/usr/bin/env bash
# Sends a span with year 2081 start/end timestamps to the local collector.
# Verifies that transform/old_traces normalizes the times to Now()
# while preserving the 1-second span duration.
set -euo pipefail

ENDPOINT="${OTLP_ENDPOINT:-http://localhost:4318/v1/traces}"

# 2081-01-01 00:00:00 UTC = 3502915200 unix seconds
START_NS=3502915200000000000
END_NS=3502915201000000000   # +1 second

TRACE_ID=$(openssl rand -hex 16)
SPAN_ID=$(openssl rand -hex 8)

curl -sS -X POST "$ENDPOINT" \
  -H 'Content-Type: application/json' \
  -d @- <<EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "bad-timestamp-demo" } }
      ]
    },
    "scopeSpans": [{
      "scope": { "name": "demo" },
      "spans": [{
        "traceId": "$TRACE_ID",
        "spanId": "$SPAN_ID",
        "name": "future-span",
        "kind": 1,
        "startTimeUnixNano": "$START_NS",
        "endTimeUnixNano": "$END_NS",
        "attributes": [
          { "key": "demo.note", "value": { "stringValue": "timestamp set to year 2081" } }
        ]
      }]
    }]
  }]
}
EOF

echo
echo "Sent span with start=$START_NS (year 2081)."
echo "Check collector logs for normalized timestamps and l9.original_* attributes:"
echo "  docker compose logs -f otel-collector"
