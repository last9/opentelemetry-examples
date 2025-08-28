#!/bin/bash

# Test script for LocalStack SQS with OpenTelemetry tracing

set -e  # Exit on any error

echo "🚀 Starting LocalStack SQS Test with OpenTelemetry Tracing"
echo "========================================================"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is required but not installed."
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo "🧹 Cleaning up..."
    docker-compose -f docker-compose.localstack.yml down
}
trap cleanup EXIT

# Start LocalStack
echo "1. Starting LocalStack..."
docker-compose -f docker-compose.localstack.yml up -d

# Wait for LocalStack to be ready
echo "2. Waiting for LocalStack to be ready..."
sleep 10

# Install dependencies
echo "3. Installing Python dependencies..."
pip install -r requirements.txt

# Setup SQS queue and send test messages
echo "4. Setting up SQS queue and sending test messages..."
python setup_localstack_sqs.py

# Configure environment variables for LocalStack
export AWS_ENDPOINT_URL=http://localhost:4566
export SQS_QUEUE_URL=http://localhost:4566/000000000000/django-test-queue
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export MAX_ITERATIONS=3
export SQS_POLLING_DELAY=2

# Configure OpenTelemetry to send traces to Last9
export OTEL_SERVICE_NAME=sqs-processor-test
export OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-"Last9Endpoint"}
export OTEL_EXPORTER_OTLP_HEADERS=${OTEL_EXPORTER_OTLP_HEADERS:-"Authorization=Basic YOUR_LAST9_TOKEN_HERE"}
export OTEL_TRACES_EXPORTER=otlp,console  # Send to both Last9 and console for verification
export OTEL_RESOURCE_ATTRIBUTES=deployment.environment=test,service.version=1.0.0
export OTEL_LOG_LEVEL=info

# Check if Last9 credentials are configured
if [[ "$OTEL_EXPORTER_OTLP_HEADERS" == *"YOUR_LAST9_TOKEN_HERE"* ]]; then
    echo "⚠️  WARNING: Last9 token not configured!"
    echo "   Please set your Last9 token:"
    echo "   export OTEL_EXPORTER_OTLP_HEADERS='Authorization=Basic YOUR_ACTUAL_TOKEN'"
    echo ""
    echo "   For now, traces will be sent to console only..."
    export OTEL_TRACES_EXPORTER=console
fi

echo "5. Environment configured:"
echo "   AWS_ENDPOINT_URL: $AWS_ENDPOINT_URL"
echo "   SQS_QUEUE_URL: $SQS_QUEUE_URL"
echo "   OTEL_SERVICE_NAME: $OTEL_SERVICE_NAME"
echo "   OTEL_TRACES_EXPORTER: $OTEL_TRACES_EXPORTER"

# Run the Django SQS processor with OpenTelemetry
echo "6. Running Django SQS processor with OpenTelemetry tracing..."
echo "   This will process messages and generate traces..."
echo ""

PYTHONPATH=. DJANGO_SETTINGS_MODULE=mysite.settings opentelemetry-instrument python manage.py runscript sqs_processor

echo ""
echo "✅ Test completed successfully!"
echo ""
echo "📊 Trace Analysis:"
echo "   - Look for spans with names like 'sqs_processor.py:run', 'sqs_processor.py:receive_message', etc."
echo "   - Each SQS operation should be wrapped in a span with proper attributes"
echo "   - Check console output for trace IDs and span information"
echo ""
echo "🔍 To run again with different settings:"
echo "   export OTEL_TRACES_EXPORTER=otlp  # To send to Last9"
echo "   export OTEL_EXPORTER_OTLP_ENDPOINT=Last9Endpoint"
echo "   export OTEL_EXPORTER_OTLP_HEADERS='Authorization=Basic YOUR_TOKEN'"
echo ""
echo "LocalStack will be stopped automatically when this script exits."