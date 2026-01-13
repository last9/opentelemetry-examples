#!/bin/bash
# HAProxy Log Generator
# Simulates customer's scenario where multiple log entries are combined

LOG_FILE="/logs/haproxy.log"
INTERVAL=10  # seconds between batches

echo "Starting HAProxy log generator..."
echo "Log file: $LOG_FILE"
echo "Interval: $INTERVAL seconds"

# Initialize with customer's exact log format (combined entries)
cat > "$LOG_FILE" << 'EOF'
2025-12-14T02:23:07.305817+00:00 ip-192-168-6-48 haproxy[927]: [WARNING]  (927) : Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed, code: 200, check duration: 10ms. 8 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
2025-12-14T02:23:07.305939+00:00 ip-192-168-6-48 haproxy[927]: Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed, code: 200, check duration: 10ms. 8 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
2025-12-14T02:23:08.412653+00:00 ip-192-168-6-48 haproxy[927]: [ERROR] Server rest-ra-backend/local_5010 is DOWN, reason: Layer4 connection problem, info: Connection refused.
EOF

echo "Initialized log file with 3 sample entries"

# Continuously generate combined logs
while true; do
    sleep "$INTERVAL"

    # Generate timestamp with microseconds
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S)
    MICROSECONDS="$(date +%N | cut -c1-6)"

    # Write multiple log entries at once (simulating the customer's issue)
    {
        echo "${TIMESTAMP}.${MICROSECONDS}+00:00 ip-192-168-6-48 haproxy[927]: [WARNING] Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed"
        echo "${TIMESTAMP}.$(expr ${MICROSECONDS} + 122)+00:00 ip-192-168-6-48 haproxy[927]: Server rest-ra-backend/local_5009 health check successful"
        echo "${TIMESTAMP}.$(expr ${MICROSECONDS} + 245)+00:00 ip-192-168-6-48 haproxy[927]: [INFO] Backend rest-ra-backend has 8 active servers"
    } >> "$LOG_FILE"

    echo "[${TIMESTAMP}.${MICROSECONDS}+00:00] Generated 3 combined log entries"
done
