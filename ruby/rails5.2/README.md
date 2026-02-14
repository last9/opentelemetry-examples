# Rails 5.2 OpenTelemetry Example

This example demonstrates OpenTelemetry instrumentation for a Rails 5.2 API application, sending traces to [Last9](https://last9.io).

## Requirements

- Ruby 2.7.x
- Rails 5.2.x
- Bundler

## Quick Start

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Configure environment variables:**
   ```bash
   export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-credentials>"
   export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io:443"
   export OTEL_TRACES_SAMPLER="always_on"
   export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
   ```

3. **Start the server:**
   ```bash
   bundle exec rails server
   ```

4. **Test the endpoints:**
   ```bash
   curl http://localhost:3000/health
   curl http://localhost:3000/users
   curl http://localhost:3000/error
   ```

## Available Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /users` | Returns mock user data |
| `GET /calculate?n=10` | Fibonacci calculation with custom spans |
| `GET /error` | Triggers an exception (for testing error traces) |
| `POST /process_order` | Nested spans example |
| `GET /external_api` | Simulated external API call |

## OpenTelemetry Configuration

The OTel configuration is in `config/initializers/opentelemetry.rb`:

- Uses OTLP exporter to send traces to Last9
- Batch span processor for efficient export
- Auto-instrumentation for Rails, ActiveRecord, Rack, and more

## Exception Tracking Fix for Rails 5.x

Rails 5.x users may encounter a known bug where **controller exceptions are not recorded as span events**. This is due to a bug in `opentelemetry-instrumentation-action_pack` v0.4.x ([GitHub Issue #635](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/635)).

The fix exists in action_pack v0.9.0+, but that version requires Rails 6.1+.

### Solution

This example includes a drop-in fix: `config/initializers/otel_exception_tracking.rb`

**For your own Rails 5.x application:**

1. Copy `config/initializers/otel_exception_tracking.rb` to your app
2. No other code changes required
3. Exceptions will automatically be captured with:
   - `exception.type`
   - `exception.message`
   - `exception.stacktrace`
   - Span status set to `ERROR`

### How It Works

The fix uses two mechanisms for Rails controllers:

1. **Rack Middleware** - Catches unhandled exceptions that bubble up
2. **ActiveSupport::Notifications** - Catches exceptions handled by `rescue_from`

And a Sidekiq server middleware for background jobs (see below).

### Manual Recording (Optional)

You can also manually record exceptions anywhere in your code:

```ruby
begin
  # risky operation
rescue => e
  OtelExceptionTracking.record(e)
  raise
end
```

## Sidekiq Exception Tracking Fix

### Problem

`opentelemetry-instrumentation-sidekiq` wraps `process_one` in `untraced` to suppress spans from Sidekiq's internal polling. However, when a job lacks propagated trace context (no `traceparent` header in the job message), the OTel tracer middleware inherits the suppressed context and creates a `NonRecordingSpan`. This means:

- `span.recording?` returns `false`
- `record_exception` and `set_attribute` are no-ops
- The span is never exported to your backend

This commonly happens when jobs are enqueued from cron schedulers, Rails console, or any context without an active OTel span.

### Solution

The fix adds a `SidekiqClearUntraced` server middleware that resets the context to `Context::ROOT` before the OTel tracer middleware runs. This uses only public APIs (`untraced?` and `Context::ROOT`).

The fix is included in `config/initializers/otel_exception_tracking.rb` and activates automatically when Sidekiq is present.

**If your file loads before Rails initializers** (e.g., from `config/application.rb`), add the Sidekiq middleware separately in your existing `Sidekiq.configure_server` block:

```ruby
class SidekiqClearUntraced
  def call(worker, msg, queue)
    if ::OpenTelemetry::Common::Utilities.untraced?
      ::OpenTelemetry::Context.with_current(::OpenTelemetry::Context::ROOT) do
        yield
      end
    else
      yield
    end
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.prepend(SidekiqClearUntraced)
  end
end
```

**Important:** Remove any `OtelExceptionTracking.record(ex)` calls from `config.error_handlers` -- Sidekiq error handlers fire after the middleware chain has unwound, so the span is already finished at that point. The tracer middleware's `in_span { yield }` already records exceptions automatically.

## Gem Versions

Key OpenTelemetry gems used:

- `opentelemetry-sdk` ~> 1.2
- `opentelemetry-exporter-otlp` ~> 0.24
- `opentelemetry-instrumentation-rails` = 0.24.1
- `opentelemetry-instrumentation-all` ~> 0.30

## Troubleshooting

### Exceptions not appearing in traces?

1. Ensure `otel_exception_tracking.rb` is loaded AFTER `opentelemetry.rb`
   - Rename to `z_otel_exception_tracking.rb` if needed for alphabetical load order
2. Check that OpenTelemetry is properly configured
3. Verify your OTLP endpoint and credentials

### Sidekiq job exceptions not appearing?

1. Ensure `SidekiqClearUntraced` middleware is in the server chain **before** the OTel `TracerMiddleware`
2. Remove `OtelExceptionTracking.record(ex)` from `config.error_handlers` (runs too late)
3. The file must be in `config/initializers/`, not `config/` (Rails.application must exist)

### Middleware load order

You can verify the Rack middleware is installed:

```bash
bundle exec rails middleware
```

Look for `OtelExceptionTracking::Middleware` before `ActionDispatch::ShowExceptions`.

## References

- [OpenTelemetry Ruby](https://opentelemetry.io/docs/languages/ruby/)
- [Last9 Documentation](https://docs.last9.io/)
- [Exception Recording Bug #635](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/635)
