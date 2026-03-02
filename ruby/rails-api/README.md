# Rails API OpenTelemetry Example

OpenTelemetry instrumentation for a Rails API application with built-in span noise reduction, sending traces to [Last9](https://last9.io).

## Prerequisites

- Ruby 3.x
- Bundler

## Quick Start

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Fill in your Last9 OTLP endpoint and credentials
   ```

3. **Start the server:**
   ```bash
   bin/rails server
   ```

4. **Send test requests:**
   ```bash
   curl http://localhost:3000/api/v1/users
   curl -X POST http://localhost:3000/api/v1/users -H 'Content-Type: application/json' -d '{"name":"Alice"}'
   ```

## Configuration

| Variable | Description |
|---|---|
| `OTEL_SERVICE_NAME` | Service name shown in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Basic <base64-credentials>` |
| `OTEL_TRACES_EXPORTER` | Set to `otlp` |

## Reducing Trace Volume

Ruby's `opentelemetry-instrumentation-all` + `use_all()` generates a large number of spans by default. This example includes several mechanisms to reduce noise.

### What's disabled

`ActionView` instrumentation is disabled — it creates a span per template and partial render, which is very high volume in full-stack apps and irrelevant for JSON APIs:

```ruby
c.use_all('OpenTelemetry::Instrumentation::ActionView' => { enabled: false })
```

### FilterSpanProcessor

A custom `OtelFilterSpanProcessor` wraps the `BatchSpanProcessor` and drops spans before export. The following are dropped by default:

| Category | Examples | Reason |
|---|---|---|
| DB transaction boundaries | `BEGIN`, `COMMIT`, `ROLLBACK` | 2 extra spans per transaction, no debug value |
| Health check paths | `/health`, `/healthz`, `/ping`, `/readyz`, `/livez` | Load balancer polling noise |
| OTLP exporter calls | Calls to your Last9 endpoint | Prevents Net::HTTP meta-tracing feedback loop |
| Noisy Redis commands | `HGET`, `HSET`, `HMGET`, `PIPELINED`, `EXPIRE`, `TTL`, etc. | High-frequency cache ops with no actionable signal |

### Tuning via environment variables

```bash
# Drop additional URL paths (comma-separated)
OTEL_FILTER_PATHS=/admin,/metrics,/internal

# Drop spans by peer hostname
OTEL_FILTER_HOSTS=internal.svc,cache.local

# Drop spans whose name contains any substring
OTEL_FILTER_SPAN_NAMES=render_partial,render_template

# Override which Redis commands to drop
OTEL_FILTER_REDIS_COMMANDS=GET,SET,DEL,EXPIRE

# Drop all spans from specific Sidekiq queues
OTEL_FILTER_SIDEKIQ_QUEUES=mailers,low

# Drop all spans from specific Sidekiq job classes
OTEL_FILTER_SIDEKIQ_JOBS=HeartbeatJob,MetricsSyncJob
```

### Probabilistic sampling

Sample a percentage of traces instead of sending everything:

```bash
OTEL_SAMPLE_RATE=0.1   # 10% of traces
OTEL_SAMPLE_RATE=0.25  # 25% of traces
```

Uses `parentbased_traceidratio` — downstream services respect the parent's sampling decision, so traces are never split mid-way.

### Sidekiq

`opentelemetry-instrumentation-sidekiq` (included via `opentelemetry-instrumentation-all`) auto-instruments Sidekiq at Rails boot — no extra setup needed for basic tracing.

`config/initializers/sidekiq.rb` adds one critical hook: it calls `OpenTelemetry.tracer_provider.shutdown` on Sidekiq stop. Without this, spans buffered in the `BatchSpanProcessor` are lost when the process receives a stop signal.

## OTel Collector Mode

Instead of sending traces directly to Last9, you can route them through an OTel Collector. The collector handles filtering and forwarding, keeping credentials out of the app container.

**Architecture:**
```
Rails app → OTel Collector (filter noise) → Last9
```

**Start with Docker Compose:**
```bash
export LAST9_OTLP_ENDPOINT=https://otlp.last9.io:443
export LAST9_OTLP_AUTH_HEADER="Basic <your-base64-credentials>"
docker compose up
```

The collector config (`otel-collector/config.yaml`) drops the same noisy spans as the in-app filter:
- `BEGIN` / `COMMIT` / `ROLLBACK` spans
- Health check paths (`/health`, `/healthz`, `/ping`, etc.)
- Noisy Redis commands (`HGET`, `HSET`, `PIPELINED`, etc.)

This is complementary to the in-app `OtelFilterSpanProcessor` — you can use either or both.

## Available Endpoints

| Endpoint | Description |
|---|---|
| `GET /api/v1/users` | List users |
| `GET /api/v1/users/:id` | Get a user |
| `POST /api/v1/users` | Create a user |
| `PUT /api/v1/users/:id` | Update a user |
| `DELETE /api/v1/users/:id` | Delete a user |

## References

- [OpenTelemetry Ruby docs](https://opentelemetry.io/docs/languages/ruby/)
- [Last9 documentation](https://last9.io/docs)
