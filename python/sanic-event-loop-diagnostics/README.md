# Python Asyncio Event Loop Diagnostics with OpenTelemetry

This example demonstrates how to monitor Python asyncio event loop health using custom OpenTelemetry instrumentation. It fills a critical gap in OTEL's out-of-box instrumentation.

## The Problem

The standard `opentelemetry-instrumentation-asyncio` package only provides:
- `asyncio.process.duration` - How long coroutines take
- `asyncio.process.count` - How many coroutines ran

**What's missing:**
- Event loop lag (delay between task scheduling and execution)
- Blocking detection (identifying code that blocks the event loop)
- Active task count
- Event loop utilization

These metrics are crucial for diagnosing async application performance issues.

## What This Example Provides

### Custom Event Loop Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `asyncio.eventloop.lag` | Gauge | Current event loop lag in seconds |
| `asyncio.eventloop.active_tasks` | Gauge | Number of active asyncio tasks |
| `asyncio.eventloop.utilization` | Gauge | Event loop utilization (0-100%) |
| `asyncio.eventloop.max_lag` | Gauge | Maximum lag observed since start |
| `asyncio.eventloop.blocking_events` | Counter | Count of detected blocking operations |
| `asyncio.eventloop.lag_distribution` | Histogram | Distribution of lag measurements |

### How It Works

The monitoring uses the **sleep-based lag detection** technique:

```python
async def _monitor_loop(self):
    while True:
        start = loop.time()
        await asyncio.sleep(0.1)  # Request 100ms sleep
        actual = loop.time() - start
        lag = actual - 0.1  # Excess time = lag
```

In a healthy event loop, `asyncio.sleep(0.1)` should resume in ~100ms. Any delay indicates the loop was busy processing other tasks or blocked by synchronous code.

This is the same approach used by:
- [New Relic Python Agent](https://docs.newrelic.com/docs/apm/agents/python-agent/supported-features/python-event-loop-diagnostics/)
- [loopmon](https://pypi.org/project/loopmon/)
- [monitored-ioloop](https://pypi.org/project/monitored-ioloop/)

## Quick Start

### Option 1: Local Development (Without Docker)

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run (without OTEL export - for local testing)
python app.py
```

Visit http://localhost:8000 to see available endpoints.

### Option 2: With Last9

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your Last9 credentials

# Install and run
pip install -r requirements.txt
python app.py
```

### Option 3: Docker Compose (Full Stack)

```bash
docker-compose up
```

## Demo Endpoints

### Monitoring
- `GET /` - Endpoint documentation
- `GET /health` - Health check with event loop status
- `GET /metrics` - Current event loop metrics (JSON)
- `GET /metrics/reset` - Reset metrics counters

### Non-Blocking Patterns (GOOD)
- `GET /async-io` - Async I/O operation
- `GET /proper-cpu?iterations=N` - CPU work offloaded to thread pool
- `GET /concurrent-tasks?count=N` - Multiple concurrent async tasks

### Blocking Patterns (BAD - For Demonstration)
- `GET /blocking-io?seconds=N` - `time.sleep()` blocks the loop
- `GET /cpu-bound?iterations=N` - CPU work in main thread blocks the loop
- `GET /blocking-hash?size=N` - Large hash computation blocks the loop

### Stress Testing
- `GET /stress-test?requests=N&concurrent=M&blocking=true/false`

## Demonstration

### See Event Loop Lag in Action

1. Start the application
2. Open two terminals

**Terminal 1 - Watch metrics:**
```bash
watch -n 0.5 'curl -s localhost:8000/metrics | jq'
```

**Terminal 2 - Trigger blocking:**
```bash
# Non-blocking (lag stays low)
curl localhost:8000/async-io

# Blocking (watch lag spike!)
curl localhost:8000/blocking-io?seconds=1

# CPU blocking (lag spikes)
curl localhost:8000/cpu-bound?iterations=50000000

# Proper CPU handling (lag stays low)
curl localhost:8000/proper-cpu?iterations=50000000
```

### Expected Results

| Endpoint | Expected Lag | Status |
|----------|-------------|--------|
| `/async-io` | < 10ms | healthy |
| `/proper-cpu` | < 10ms | healthy |
| `/blocking-io?seconds=1` | ~1000ms | critical |
| `/cpu-bound?iterations=50000000` | 500-2000ms | critical |

## Understanding the Metrics

### Lag Interpretation

| Lag | Status | Meaning |
|-----|--------|---------|
| < 10ms | healthy | Event loop is responsive |
| 10-50ms | ok | Minor delays, acceptable for most apps |
| 50-500ms | degraded | Noticeable delays, investigate |
| > 500ms | critical | Significant blocking, fix immediately |

### Common Causes of High Lag

1. **Synchronous I/O** - `time.sleep()`, synchronous HTTP clients (`requests`), file I/O
2. **CPU-bound work** - Heavy computation, JSON parsing large files, compression
3. **Blocking database calls** - Sync database drivers in async code
4. **GIL contention** - Multiple CPU-bound tasks competing

### Solutions

| Problem | Solution |
|---------|----------|
| `time.sleep()` | Use `asyncio.sleep()` |
| CPU-bound work | Use `loop.run_in_executor()` |
| Sync HTTP client | Use `aiohttp` or `httpx` |
| Sync database | Use async drivers (asyncpg, aiomysql) |

## Configuration

### Environment Variables

All configuration is done via environment variables. Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

#### Service Identification (Required for Last9)

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Service name shown in Last9 | `sanic-event-loop-demo` |
| `SERVICE_VERSION` | Service version for tracking deployments | - |
| `DEPLOYMENT_ENVIRONMENT` | Environment (production/staging/development) | `development` |
| `SERVICE_NAMESPACE` | Logical grouping (e.g., "payments", "user-management") | - |

```bash
OTEL_SERVICE_NAME=my-async-service
SERVICE_VERSION=1.0.0
DEPLOYMENT_ENVIRONMENT=production
SERVICE_NAMESPACE=backend
```

#### OTLP Export Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Base OTLP endpoint (Last9) | - |
| `OTEL_EXPORTER_OTLP_HEADERS` | Authentication headers | - |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Protocol (`http/protobuf` or `grpc`) | `http/protobuf` |
| `OTEL_METRIC_EXPORT_INTERVAL_MS` | Metric export interval in milliseconds | `60000` (1 minute) |

```bash
# Last9 OTLP endpoint
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io

# Authentication (Basic auth)
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <base64-credentials>

# Metric export interval (default: 60 seconds)
# For local testing, use 10000 (10 seconds) to see metrics faster
OTEL_METRIC_EXPORT_INTERVAL_MS=60000
```

#### Sampling Configuration (Optional)

| Variable | Description | Default |
|----------|-------------|---------|
| `OTEL_TRACES_SAMPLER` | Sampler type (`always_on`, `always_off`, `traceidratio`) | `always_on` |
| `OTEL_TRACES_SAMPLER_ARG` | Sampler argument (for traceidratio) | `0.1` |

```bash
# Sample 10% of traces
OTEL_TRACES_SAMPLER=traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

#### Application Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `HOST` | Server bind address | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `DEBUG` | Enable debug mode | `true` |

#### Additional Resource Attributes (Optional)

Add custom attributes via `OTEL_RESOURCE_ATTRIBUTES`:

```bash
OTEL_RESOURCE_ATTRIBUTES=team=platform,cost_center=engineering,region=us-west-2
```

### Kubernetes Environment Variables

When running in Kubernetes, set these via Downward API:

```bash
# Kubernetes attributes (auto-detected in K8s, or set manually)
OTEL_RD_K8S_POD_NAME=my-pod-abc123
OTEL_RD_K8S_NAMESPACE_NAME=default
OTEL_RD_K8S_CONTAINER_NAME=app
OTEL_RD_K8S_DEPLOYMENT_NAME=my-deployment
OTEL_RD_K8S_NODE_NAME=node-1
OTEL_RD_K8S_CLUSTER_NAME=my-cluster
```

Example Kubernetes deployment spec:

```yaml
env:
  - name: OTEL_RD_K8S_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: OTEL_RD_K8S_NAMESPACE_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: OTEL_RD_K8S_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
```

### Monitor Configuration

In `app.py`, you can customize the monitor:

```python
event_loop_monitor = EventLoopMonitor(
    meter=meter,
    interval=0.1,           # Check every 100ms (default)
    blocking_threshold=0.05, # 50ms = warning (default)
    critical_threshold=0.5,  # 500ms = critical (default)
    service_name=service_name
)
```

## Alerting Recommendations

### PromQL Queries (for Last9)

```promql
# Average lag over 5 minutes
avg_over_time(asyncio_eventloop_lag[5m])

# P99 lag from histogram
histogram_quantile(0.99, rate(asyncio_eventloop_lag_distribution_bucket[5m]))

# Blocking events rate
rate(asyncio_eventloop_blocking_events_total[5m])

# Alert: High event loop lag
asyncio_eventloop_lag > 0.1  # 100ms threshold
```

### Recommended Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| Event loop degraded | lag > 50ms for 2min | warning |
| Event loop critical | lag > 500ms for 1min | critical |
| Frequent blocking | blocking_events rate > 10/min | warning |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Sanic Application                        │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐ │
│  │   Endpoints   │   │  OTEL Tracer  │   │  OTEL Meter   │ │
│  └───────────────┘   └───────────────┘   └───────────────┘ │
│                              │                   │          │
│                              │     ┌─────────────┴───────┐  │
│                              │     │ EventLoopMonitor    │  │
│                              │     │ - lag measurement   │  │
│                              │     │ - task counting     │  │
│                              │     │ - blocking detection│  │
│                              │     └─────────────────────┘  │
└──────────────────────────────┼───────────────┼──────────────┘
                               │               │
                               ▼               ▼
                      ┌─────────────────────────────┐
                      │     OTLP Exporter           │
                      │  (traces + metrics)         │
                      └─────────────────────────────┘
                                    │
                                    ▼
                      ┌─────────────────────────────┐
                      │   Last9 / OTEL Collector    │
                      └─────────────────────────────┘
```

## Resource Detection

The application automatically detects and populates resource attributes based on the runtime environment. This helps identify your service in Last9 and other observability platforms.

### Auto-Detected Attributes

| Category | Attributes |
|----------|------------|
| **Service** | `service.name`, `service.version`, `deployment.environment` |
| **Process** | `process.pid`, `process.runtime.name`, `process.runtime.version` |
| **Host** | `host.name`, `host.arch` |
| **OS** | `os.type`, `os.version` |

### Cloud Provider Detection

Install the appropriate package for your cloud provider:

#### AWS (EC2, ECS, EKS, Lambda)

```bash
pip install opentelemetry-sdk-extension-aws
```

Auto-detected attributes:
- `cloud.provider=aws`, `cloud.platform`, `cloud.region`, `cloud.account.id`
- EC2: `host.id`, `host.type`, `host.image.id`
- ECS: `aws.ecs.container.arn`, `aws.ecs.cluster.arn`, `aws.ecs.task.arn`
- EKS: `k8s.cluster.name`
- Lambda: `faas.name`, `faas.version`, `aws.log.group.names`

#### GCP (GCE, GKE, Cloud Run, Cloud Functions)

```bash
pip install opentelemetry-resourcedetector-gcp
```

Auto-detected attributes:
- `cloud.provider=gcp`, `cloud.platform`, `cloud.region`, `cloud.account.id`
- GCE: `host.id`, `host.name`, `host.type`
- GKE: `k8s.cluster.name`
- Cloud Run: `faas.name`, `faas.version`, `gcp.cloud_run.job.*`

#### Kubernetes

```bash
pip install opentelemetry-resourcedetector-kubernetes
```

Auto-detected attributes:
- `k8s.pod.name`, `k8s.pod.uid`, `k8s.namespace.name`
- `k8s.container.name`, `k8s.deployment.name`, `k8s.node.name`
- `container.id`

### Example Output

When running with all detectors enabled:

```
OpenTelemetry Configuration:
  Metric export interval: 60000ms
  OTLP endpoint: https://otlp.last9.io

OpenTelemetry Resource Attributes:
  deployment.environment: staging
  host.arch: arm64
  host.name: my-host
  k8s.cluster.name: demo-cluster
  k8s.container.name: app
  k8s.deployment.name: sanic-demo
  k8s.namespace.name: default
  k8s.node.name: node-1
  k8s.pod.name: sanic-demo-abc123
  os.type: linux
  os.version: 5.15.0
  process.pid: 1
  process.runtime.name: cpython
  process.runtime.version: 3.11.0
  service.name: sanic-event-loop-demo
  service.version: 1.0.0
  telemetry.sdk.language: python
  telemetry.sdk.name: opentelemetry
  telemetry.sdk.version: 1.39.1
```

## Files

| File | Purpose |
|------|---------|
| `app.py` | Main Sanic application with demo endpoints |
| `event_loop_monitor.py` | Custom event loop monitoring with OTEL metrics |
| `otel_setup.py` | OpenTelemetry tracer + meter + resource detection configuration |
| `requirements.txt` | Python dependencies |
| `docker-compose.yml` | Local testing stack |
| `otel-collector-config.yaml` | OTEL Collector configuration |

## Integrating Into Your Application

To add event loop monitoring to your existing async application:

1. Copy `event_loop_monitor.py` to your project
2. Initialize the monitor on startup:

```python
from opentelemetry import metrics
from event_loop_monitor import EventLoopMonitor

# After setting up your MeterProvider
meter = metrics.get_meter(__name__)

monitor = EventLoopMonitor(
    meter=meter,
    service_name="my-service"
)

# Start monitoring (in async context)
await monitor.start()

# On shutdown
await monitor.stop()
```

## References

### Event Loop Monitoring
- [OpenTelemetry Python](https://opentelemetry.io/docs/languages/python/)
- [OpenTelemetry asyncio Instrumentation](https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/asyncio/asyncio.html)
- [Monitoring Async Python - MeadSteve's Blog](https://blog.meadsteve.dev/programming/2020/02/23/monitoring-async-python/)
- [Python Event Loop Diagnostics - New Relic](https://docs.newrelic.com/docs/apm/agents/python-agent/supported-features/python-event-loop-diagnostics/)
- [loopmon](https://pypi.org/project/loopmon/)
- [Python asyncio Debug Mode](https://docs.python.org/3/library/asyncio-dev.html)

### Resource Detectors
- [AWS Distro for OpenTelemetry Python](https://aws-otel.github.io/docs/getting-started/python-sdk/manual-instr/)
- [opentelemetry-resourcedetector-gcp on PyPI](https://pypi.org/project/opentelemetry-resourcedetector-gcp/)
- [Google Cloud OpenTelemetry Documentation](https://google-cloud-opentelemetry.readthedocs.io/en/latest/)
- [opentelemetry-resourcedetector-kubernetes on PyPI](https://pypi.org/project/opentelemetry-resourcedetector-kubernetes/)
- [OpenTelemetry Resource Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/resource/)
