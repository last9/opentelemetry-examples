#!/bin/bash
# End-to-end local test using LocalStack.
#
# This script:
#   1. Starts LocalStack (SQS)
#   2. Creates the SQS queue
#   3. Starts the producer (Flask app)
#   4. Sends a test message via /publish
#   5. Reads the message from SQS to verify trace context in MessageAttributes
#
# Prerequisites:
#   - Docker running
#   - Python venv with requirements installed
#
# Usage:
#   chmod +x test_local.sh
#   ./test_local.sh

set -e

QUEUE_NAME="test-trace-queue"
LOCALSTACK_URL="http://localhost:4566"

echo "=== Step 1: Start LocalStack ==="
docker run -d --name localstack-sqs -p 4566:4566 \
    -e SERVICES=sqs \
    localstack/localstack 2>/dev/null || echo "LocalStack already running"

echo "Waiting for LocalStack..."
sleep 5

echo ""
echo "=== Step 2: Create SQS queue ==="
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1
export AWS_ENDPOINT_URL="$LOCALSTACK_URL"

aws --endpoint-url "$LOCALSTACK_URL" sqs create-queue \
    --queue-name "$QUEUE_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || true

QUEUE_URL=$(aws --endpoint-url "$LOCALSTACK_URL" sqs get-queue-url \
    --queue-name "$QUEUE_NAME" --region "$AWS_REGION" \
    --query QueueUrl --output text)

echo "Queue URL: $QUEUE_URL"

echo ""
echo "=== Step 3: Send a message via the producer ==="
export SQS_QUEUE_URL="$QUEUE_URL"
export OTEL_SERVICE_NAME="publisher-service"
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
export OTEL_EXPORTER_OTLP_HEADERS="${OTEL_EXPORTER_OTLP_HEADERS:-}"

# Start Flask app in the background
python app.py &
APP_PID=$!
sleep 2

# Send a test message
echo "Sending test message..."
curl -s -X POST http://localhost:8080/publish \
    -H "Content-Type: application/json" \
    -d '{"action": "upload", "file": "test.csv"}' | python -m json.tool

echo ""
echo "=== Step 4: Verify trace context in SQS message ==="
MESSAGES=$(aws --endpoint-url "$LOCALSTACK_URL" sqs receive-message \
    --queue-url "$QUEUE_URL" \
    --region "$AWS_REGION" \
    --message-attribute-names All \
    --max-number-of-messages 1)

echo "$MESSAGES" | python -m json.tool

# Check for traceparent attribute
if echo "$MESSAGES" | grep -q "traceparent"; then
    echo ""
    echo "SUCCESS: traceparent found in SQS MessageAttributes!"
    echo "The downstream Lambda consumer will be able to link to this trace."
else
    echo ""
    echo "FAILURE: traceparent NOT found in SQS MessageAttributes."
    echo "Check that OpenTelemetry propagators are configured correctly."
fi

echo ""
echo "=== Step 5: Simulate Lambda processing ==="
# Write SQS messages to a temp file to avoid shell injection via inline Python
echo "$MESSAGES" > /tmp/sqs_messages.json

python - "$QUEUE_NAME" <<'PYEOF'
import json, sys

queue_name = sys.argv[1]

with open("/tmp/sqs_messages.json") as f:
    msgs = json.load(f)

if msgs.get("Messages"):
    m = msgs["Messages"][0]
    # Convert to ESM format (lowercase keys)
    esm_attrs = {}
    for k, v in m.get("MessageAttributes", {}).items():
        esm_attrs[k] = {"stringValue": v.get("StringValue", ""), "dataType": v.get("DataType", "String")}
    event = {
        "Records": [{
            "messageId": m["MessageId"],
            "body": m["Body"],
            "messageAttributes": esm_attrs,
            "eventSourceARN": f"arn:aws:sqs:us-east-1:000000000000:{queue_name}",
        }]
    }
    print(json.dumps(event, indent=2))
    # Invoke the handler
    sys.path.insert(0, ".")
    from lambda_function import handler
    result = handler(event, None)
    print("Lambda result:", json.dumps(result, indent=2))
else:
    print("No messages found")
PYEOF

echo ""
echo "=== Cleanup ==="
kill $APP_PID 2>/dev/null || true
echo "Stopped Flask app."
echo ""
echo "To stop LocalStack: docker rm -f localstack-sqs"
echo ""
echo "Done! Check your Last9 dashboard for linked traces."
