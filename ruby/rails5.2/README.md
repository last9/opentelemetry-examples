# Rails 5.2 OpenTelemetry Example

OpenTelemetry instrumentation for a Rails 5.2 API application with built-in span noise reduction, sending traces to [Last9](https://last9.io).

## Prerequisites

- Ruby 2.7.x
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
   bundle exec rails server
   ```

4. **Send test requests:**
   ```bash
   curl http://localhost:3000/health
   curl http://localhost:3000/users
   curl http://localhost:3000/calculate?n=10
   curl -X POST http://localhost:3000/process_order
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

### Sidekiq

`opentelemetry-instrumentation-sidekiq` (included via `opentelemetry-instrumentation-all`) auto-instruments Sidekiq at Rails boot — no extra setup needed for basic tracing.

`config/initializers/sidekiq.rb` adds one critical hook: it calls `OpenTelemetry.tracer_provider.shutdown` on Sidekiq stop. Without this, spans buffered in the `BatchSpanProcessor` are lost when the process receives a stop signal.

### Probabilistic sampling

Sample a percentage of traces instead of sending everything:

```bash
OTEL_SAMPLE_RATE=0.1   # 10% of traces
OTEL_SAMPLE_RATE=0.25  # 25% of traces
```

Uses `parentbased_traceidratio` — downstream services respect the parent's sampling decision, so traces are never split mid-way.

## Available Endpoints

| Endpoint | Description |
|---|---|
| `GET /health` | Health check |
| `GET /users` | Returns mock user data |
| `GET /calculate?n=10` | Fibonacci with a custom span |
| `GET /error` | Triggers an exception (tests error trace recording) |
| `POST /process_order` | Nested spans example |
| `GET /external_api` | Simulated external HTTP call |

## Exception Tracking Fix (Rails 5.x)

`config/initializers/otel_exception_tracking.rb` fixes two known issues:

**1. Controller exceptions not recorded ([opentelemetry-ruby-contrib #635](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/635))**

`opentelemetry-instrumentation-action_pack` v0.4.x doesn't record controller exceptions as span events. The fix requires Rails 6.1+ to land upstream. This workaround uses Rack middleware + `ActiveSupport::Notifications` to capture both unhandled exceptions and those handled via `rescue_from`.

**2. Sidekiq job exceptions silently dropped**

`opentelemetry-instrumentation-sidekiq` wraps `process_one` in `untraced` to suppress Sidekiq's internal polling spans. When a job has no propagated trace context (no `traceparent` header — the common case for jobs enqueued without HTTP context), the `tracer_middleware` inherits the suppressed context and creates a `NonRecordingSpan`. Exceptions on those spans are silently dropped.

The fix is `SidekiqClearUntraced`, a Sidekiq server middleware inserted before the OTel `TracerMiddleware` that replaces the suppressed context with `Context::ROOT`, ensuring job spans are always recording.

**To use in your own app:** copy `config/initializers/otel_exception_tracking.rb` into your app. No other changes needed.

To record exceptions manually anywhere in your code:

```ruby
rescue => e
  OtelExceptionTracking.record(e)
  raise
end
```

## References

- [OpenTelemetry Ruby docs](https://opentelemetry.io/docs/languages/ruby/)
- [Last9 documentation](https://last9.io/docs)
