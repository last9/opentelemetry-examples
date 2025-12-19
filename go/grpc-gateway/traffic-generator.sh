#!/bin/bash

# Traffic Generator for gRPC-Gateway Demo
# Generates varied traffic patterns to demonstrate OpenTelemetry tracing

echo "🚀 Starting traffic generator for gRPC-Gateway demo..."
echo ""

# List of sample names for variety
NAMES=("Alice" "Bob" "Charlie" "Diana" "Eve" "Frank" "Grace" "Henry" "Ivy" "Jack" "Kate" "Leo" "Maya" "Nina" "Oscar" "Paul" "Quinn" "Ruby" "Sam" "Tina")

# Counter for requests
COUNT=0
TOTAL_REQUESTS=50

echo "Generating $TOTAL_REQUESTS requests..."
echo ""

while [ $COUNT -lt $TOTAL_REQUESTS ]; do
    # Pick a random name
    NAME=${NAMES[$RANDOM % ${#NAMES[@]}]}

    # Send HTTP request
    echo "[$((COUNT+1))/$TOTAL_REQUESTS] Sending request for: $NAME"

    RESPONSE=$(curl -s -X POST http://localhost:8080/v1/greeter/hello \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$NAME\"}" 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "  ✓ Response: $RESPONSE"
    else
        echo "  ✗ Request failed"
    fi

    # Increment counter
    COUNT=$((COUNT+1))

    # Random delay between 0.5 and 2 seconds
    DELAY=$(awk -v min=0.5 -v max=2 'BEGIN{srand(); print min+rand()*(max-min)}')
    sleep $DELAY
done

echo ""
echo "✅ Traffic generation complete!"
echo "   Total requests sent: $TOTAL_REQUESTS"
echo ""
echo "🔍 Check your Last9 dashboard for traces at: https://app.last9.io"
