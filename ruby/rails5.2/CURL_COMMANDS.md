# Curl Commands for Testing OpenTelemetry Traces

Use these curl commands to test your Rails app and verify traces are being sent to Last9.

## Prerequisites

1. Ensure your Rails server is running:
   ```bash
   rails server
   ```

2. Make sure your `.env` file has the correct Last9 OTLP configuration:
   - `OTEL_EXPORTER_OTLP_ENDPOINT`
   - `OTEL_EXPORTER_OTLP_HEADERS`

## Individual Curl Commands

### 1. Health Check (Simple Trace)
```bash
curl -X GET http://localhost:3000/health
```
Expected: Returns service status and creates a basic HTTP trace

### 2. User List (Database Simulation)
```bash
curl -X GET http://localhost:3000/users
```
Expected: Returns user list with simulated DB latency in trace

### 3. Calculation with Parameters
```bash
# Small calculation
curl -X GET "http://localhost:3000/calculate?n=5"

# Medium calculation
curl -X GET "http://localhost:3000/calculate?n=10"

# Larger calculation (slower)
curl -X GET "http://localhost:3000/calculate?n=15"
```
Expected: Creates traces with custom spans showing calculation details

### 4. Error Generation (Error Trace)
```bash
curl -X GET http://localhost:3000/error
```
Expected: Returns 500 error and creates error trace with stack trace

### 5. Complex Order Processing (Nested Spans)
```bash
# Without order ID (generates random ID)
curl -X POST http://localhost:3000/process_order \
  -H "Content-Type: application/json" \
  -d '{"items": ["product1", "product2"], "quantity": 2}'

# With specific order ID
curl -X POST "http://localhost:3000/process_order?order_id=ORD-TEST-123" \
  -H "Content-Type: application/json" \
  -d '{"items": ["product3", "product4"], "quantity": 5}'
```
Expected: Creates nested spans for order validation, pricing, and payment

### 6. External API Simulation
```bash
curl -X GET http://localhost:3000/external_api
```
Expected: Creates trace showing simulated external API call

## Batch Testing

### Run Multiple Requests
```bash
# Send 5 health checks
for i in {1..5}; do
  curl -s http://localhost:3000/health
  echo ""
  sleep 1
done

# Mixed endpoint testing
curl http://localhost:3000/health && echo "" && \
curl http://localhost:3000/users && echo "" && \
curl "http://localhost:3000/calculate?n=7" && echo "" && \
curl http://localhost:3000/external_api
```

### Load Testing (Parallel Requests)
```bash
# Send 10 parallel requests
for i in {1..10}; do
  curl -s http://localhost:3000/users &
done
wait
```

## Automated Testing

Run the included test script for comprehensive testing:
```bash
./test_traces.sh
```

## Verifying Traces in Last9

After running these commands, check your Last9 dashboard:

1. Navigate to your Last9 APM/Traces section
2. Look for service name: `ruby-on-rails-api-service`
3. You should see:
   - HTTP request spans for each endpoint
   - Custom spans for calculations and order processing
   - Error traces with stack traces from `/error`
   - Latency metrics for each operation
   - Custom attributes (order IDs, calculation inputs, etc.)

## Trace Attributes to Look For

- **Service Information**:
  - `service.name`: ruby-on-rails-api-service
  - `service.version`: 0.0.0
  - `deployment.environment`: development/production

- **HTTP Attributes**:
  - `http.method`: GET/POST
  - `http.status_code`: 200/500
  - `http.target`: /health, /users, etc.
  - `http.url`: Full request URL

- **Custom Attributes** (in custom spans):
  - `calculation.type`: fibonacci
  - `calculation.input`: Input number
  - `calculation.result`: Computed result
  - `order.id`: Order identifier
  - `payment.status`: Payment result

## Troubleshooting

If traces are not appearing in Last9:

1. Check Rails logs for OpenTelemetry initialization:
   ```bash
   tail -f log/development.log | grep -i opentelemetry
   ```

2. Verify environment variables are loaded:
   ```bash
   rails console
   > ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
   > ENV['OTEL_EXPORTER_OTLP_HEADERS']
   ```

3. Check for errors in Rails server output

4. Ensure Last9 OTLP endpoint is reachable:
   ```bash
   curl -I $OTEL_EXPORTER_OTLP_ENDPOINT
   ```