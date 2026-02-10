# Sanic Event Loop Diagnostics with OpenTelemetry

Monitor and diagnose Python asyncio event loop health in Sanic applications using OpenTelemetry metrics.

## Overview

This example demonstrates comprehensive event loop monitoring for Sanic (Python async web framework) applications. It tracks:

- **Event Loop Lag** - Measures delay in event loop responsiveness
- **Event Loop Utilization** - Percentage of time event loop is busy
- **Per-Request Metrics** - Wait time vs execution time for each request
- **Blocking Operations** - Detects and counts synchronous blocking calls
- **Active Tasks** - Tracks number of concurrent asyncio tasks

All metrics are exported using OpenTelemetry Protocol (OTLP) and can be visualized in otlp.

## Use Cases

- Identify slow endpoints causing event loop blocking
- Monitor event loop health in production
- Detect performance degradation over time
- Compare event loop behavior across services
- Diagnose high latency issues in async applications

## Architecture

```
┌─────────────────┐
│  Sanic App      │
│                 │
│  ┌───────────┐  │
│  │ Middleware│  │  Captures per-request metrics
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │Event Loop │  │  Background monitoring
│  │Diagnostics│  │  (checks lag every 100ms)
│  └─────┬─────┘  │
└────────┼────────┘
         │
         │ OTLP Export
         ▼
   ┌────────────┐
   │OTLP/OTEL  │
   │Collector   │
   └──────┬─────┘
```

## Prerequisites

- Python 3.11+
- Sanic 23.12+
- OpenTelemetry Python SDK
- Access to OTLP or OpenTelemetry Collector

## Quick Start

### 1. Install Dependencies

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure OTLP Endpoint

Edit `otel_config_production.py` and update:

```python
# Your OTLP endpoint
otlp_endpoint = "YOUR_OTLP_ENDPOINT"

# Your authentication token (Base64 encoded)
otlp_headers = {"authorization": "Basic YOUR_TOKEN_HERE"}
```

### 3. Run Demo Application

```bash
python app.py
```

The demo app will start on `http://localhost:8000` with several test endpoints:

- `GET /` - Root endpoint
- `GET /fast` - Fast endpoint (~10ms)
- `GET /slow` - Slow endpoint (~500ms)
- `GET /health` - Health check
- `GET /blocking` - Simulates blocking operation (for testing)

### 4. Generate Test Traffic

```bash
# In another terminal
curl http://localhost:8000/fast
curl http://localhost:8000/slow
curl http://localhost:8000/health
```

### 5. Visualize Metrics

Query your metrics in your observability platform using PromQL:

```promql
# Check event loop lag P95
histogram_quantile(0.95, rate(event_loop_lag_milliseconds_bucket{service_name="sanic-eventloop-demo"}[5m]))

# Check event loop utilization
event_loop_utilization_percent{service_name="sanic-eventloop-demo"}

# Check wait time by endpoint
histogram_quantile(0.95, rate(event_loop_wait_time_milliseconds_bucket[5m])) by (endpoint)
```

## Files

| File | Description |
|------|-------------|
| `event_loop_diagnostics.py` | Core event loop monitoring module |
| `sanic_middleware.py` | Sanic middleware for request instrumentation |
| `otel_config_production.py` | OpenTelemetry configuration for OTLP |
| `app.py` | Demo Sanic application |
| `requirements.txt` | Python dependencies |

## Integration into Your Application

### Step 1: Add to Your Sanic App

```python
from sanic import Sanic
from event_loop_diagnostics import EventLoopDiagnostics
from sanic_middleware import setup_event_loop_middleware
from otel_config_production import setup_otel

# Initialize OTEL
setup_otel()

app = Sanic("your-service-name")

# Setup event loop diagnostics
diagnostics = EventLoopDiagnostics(service_name="your-service-name")
setup_event_loop_middleware(app, diagnostics)

# Your routes...
@app.route("/api/endpoint")
async def endpoint(request):
    return response.json({"status": "ok"})
```

### Step 2: Deploy

Deploy your application with environment variables for Kubernetes pod metadata:

```yaml
env:
  - name: SERVICE_NAME
    value: "your-service-name"
  - name: K8S_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: K8S_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

### Step 3: Verify Metrics

After deployment, verify metrics are being exported:

```promql
# Check all event loop metrics
{service_name="your-service-name", __name__=~"event_loop.*"}

# Check lag histogram
event_loop_lag_milliseconds_bucket{service_name="your-service-name"}
```

## Metrics Exported

### Histograms

| Metric Name | Prometheus Name | Description |
|-------------|-----------------|-------------|
| `event_loop.lag` | `event_loop_lag_milliseconds_bucket` | Event loop lag distribution |
| `event_loop.wait_time` | `event_loop_wait_time_milliseconds_bucket` | Request wait time (time in queue) |
| `event_loop.execution_time` | `event_loop_execution_time_milliseconds_bucket` | Request execution time (time on event loop) |

### Gauges

| Metric Name | Prometheus Name | Description |
|-------------|-----------------|-------------|
| `event_loop.utilization` | `event_loop_utilization_percent` | Event loop utilization (0-100%) |
| `event_loop.max_lag` | `event_loop_max_lag_milliseconds` | Maximum lag observed |

### Counters

| Metric Name | Prometheus Name | Description |
|-------------|-----------------|-------------|
| `event_loop.blocking_calls` | `event_loop_blocking_calls_total` | Count of blocking operations detected |
| `event_loop.tasks.active` | `event_loop_tasks_active` | Number of active asyncio tasks (UpDownCounter) |

## Configuration Options

### EventLoopDiagnostics Options

```python
diagnostics = EventLoopDiagnostics(
    service_name="my-service",          # Service name for metrics
    meter_name="sanic.event_loop",      # OTEL meter name
    check_interval_ms=100,               # How often to check lag (default: 100ms)
    blocking_threshold_ms=50,            # Threshold for blocking detection (default: 50ms)
    enabled=True                         # Enable/disable monitoring
)
```

### OTLP Configuration

Edit `otel_config_production.py`:

```python
# OTLP endpoint
otlp_endpoint = "YOUR_OTLP_ENDPOINT"

# Auth headers
otlp_headers = {"authorization": "Basic YOUR_TOKEN"}

# Export interval (milliseconds)
export_interval_millis=60000  # 60 seconds
```


## Troubleshooting

### Metrics Not Appearing

1. **Check OTLP connectivity:**
   ```bash
   curl -v YOUR_OTLP_ENDPOINT
   ```

2. **Verify authentication:**
   - Ensure token is Base64 encoded
   - Check header format: `"authorization": "Basic <token>"`

3. **Check metrics are being created:**
   Run the app and check console for any errors



## Performance Impact

- **CPU Overhead**: < 1% (background check every 100ms)
- **Memory Overhead**: ~2-5 MB (metric state)
- **Network**: ~1-5 KB/minute (depending on request rate)

## Best Practices

1. **Set Appropriate Thresholds**
   - Adjust `blocking_threshold_ms` based on your SLOs
   - Typical values: 50ms for high-performance, 100ms for standard

2. **Monitor in Production**
   - Start with a small percentage of traffic
   - Use feature flags to enable/disable monitoring

3. **Alert on High Lag**
   ```promql
   # Alert when P95 lag > 50ms for 5 minutes
   histogram_quantile(0.95, rate(event_loop_lag_milliseconds_bucket[5m])) > 50
   ```

4. **Correlate with Business Metrics**
   - Compare lag with error rates
   - Check if slow endpoints correlate with customer complaints

## Support

For issues or questions:
- GitHub Issues: [opentelemetry-examples](https://github.com/last9/opentelemetry-examples)

