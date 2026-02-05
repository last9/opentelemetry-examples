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

The fix uses two mechanisms:

1. **Rack Middleware** - Catches unhandled exceptions that bubble up
2. **ActiveSupport::Notifications** - Catches exceptions handled by `rescue_from`

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

### Middleware load order

You can verify the middleware is installed:

```bash
bundle exec rails middleware
```

Look for `OpenTelemetry::Instrumentation::ExceptionTracking::Middleware` before `ActionDispatch::ShowExceptions`.

## References

- [OpenTelemetry Ruby](https://opentelemetry.io/docs/languages/ruby/)
- [Last9 Documentation](https://docs.last9.io/)
- [Exception Recording Bug #635](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/635)
