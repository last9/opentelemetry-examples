# Sanic + OpenTelemetry Demo for Last9

A complete working example of Sanic microservices with OpenTelemetry distributed tracing to Last9.

## Features

- Two Sanic services demonstrating distributed tracing
- Full OpenTelemetry integration with Last9
- Automatic HTTP client instrumentation
- Proper trace context propagation
- Support for database instrumentation

## Project Structure

```
.
├── service-a/          # Service A (port 8001)
│   └── app.py         # Fully instrumented Sanic app
├── service-b/          # Service B (port 8002)
│   └── app.py         # Fully instrumented Sanic app
├── requirements-otel.txt
└── README.md
```

## Quick Start

### 1. Install dependencies

```bash
pip install -r requirements-otel.txt
```

### 2. Configure the environment

```bash
export OTEL_SERVICE_NAME=service-b
export OTEL_EXPORTER_OTLP_ENDPOINT="your_last9_endpoint"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-credentials>"
```

### 3. Run Service B (Terminal 1)

```bash
python service-b/app.py
```

Service B runs on http://localhost:8002

### 4. Run Service A (Terminal 2)

```bash
export OTEL_SERVICE_NAME=service-a
export OTEL_EXPORTER_OTLP_ENDPOINT="your_last9_endpoint"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-credentials>"

python service-a/app.py
```

Service A runs on http://localhost:8001

### 5. Generate test traffic

```bash
# Test distributed tracing across services
curl http://localhost:8001/call-chain

# Test individual services
curl http://localhost:8002/health
curl http://localhost:8001/health
```

### 6. View traces in Last9

1. Go to Last9 Dashboard → APM → Traces
2. Filter by service names: `service-a` or `service-b`
3. You should see:
   - SERVER spans: Incoming HTTP requests
   - CLIENT spans: Outgoing HTTP calls
   - Full trace context propagation across services

## Available Endpoints

### Service A (Port 8001)
- `GET /health` - Health check
- `GET /internal` - Internal endpoint
- `GET /call-service-b` - Calls Service B
- `GET /call-self` - Calls its own /internal endpoint
- `GET /call-chain` - Calls both Service B and itself (full distributed trace)

### Service B (Port 8002)
- `GET /health` - Health check
- `GET /process` - Data processing endpoint

## What Makes This Work

This demo solves the Sanic multiprocessing challenge by:

1. Initializing OpenTelemetry in worker processes using `@app.before_server_start`
2. Creating SERVER spans with custom middleware
3. Extracting and propagating trace context from HTTP headers
4. Auto-instrumenting HTTP clients (aiohttp) for CLIENT spans

