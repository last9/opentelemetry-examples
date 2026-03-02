# Rails Log-Trace Correlation Examples

This directory demonstrates **4 different approaches** to integrating OpenTelemetry log-trace correlation with Rails logging. These examples show how to add `trace_id` and `span_id` to your Rails application logs for correlation with distributed traces in Last9 or any OpenTelemetry-compatible backend.

## What is Log-Trace Correlation?

Log-trace correlation adds OpenTelemetry trace context (`trace_id` and `span_id`) to your application logs. This allows observability platforms to link log entries with their corresponding distributed traces, making debugging significantly faster by showing both what happened (traces) and contextual details (logs) in one view.

## Implementation Files

This directory contains standalone implementation files that can be added to any Rails application:

### Mode 1: Rails Logger (config/initializers/log_correlation_rails_logger.rb)
- **Format:** Text with prepended trace context
- **Best for:** Development, simple applications
- **Output:** `trace_id=xxx span_id=yyy message`

### Mode 2: Lograge (config/initializers/log_correlation_lograge.rb)
- **Format:** Structured JSON
- **Best for:** Production, cloud-native apps
- **Output:** JSON with trace_id and span_id fields
- **Requires:** `gem 'lograge'`

### Mode 3: Semantic Logger (config/initializers/log_correlation_semantic_logger.rb)
- **Format:** Tagged logs with named trace fields
- **Best for:** High-volume production, enterprises
- **Output:** Logs with {trace_id: "xxx", span_id: "yyy"} tags
- **Requires:** `gem 'rails_semantic_logger'`

### Mode 4: Custom JSON Formatter (config/initializers/log_correlation_json.rb)
- **Format:** Pure JSON
- **Best for:** Kubernetes, cloud log aggregation
- **Output:** JSON object per log line

## Quick Start

### Option A: Use with Existing Rails App

Copy any initializer file to your Rails app:

```bash
# For example, to use Rails Logger mode:
cp config/initializers/log_correlation_rails_logger.rb your_rails_app/config/initializers/
```

Ensure your app has OpenTelemetry configured:

```ruby
# Gemfile
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
gem 'opentelemetry-instrumentation-all'
```

### Option B: Use with Complete Rails Example

See `../rails-api/` for a complete working Rails application with log-trace correlation enabled.

## How It Works

All implementations use the same OpenTelemetry pattern:

```ruby
span = OpenTelemetry::Trace.current_span
context = span.context

trace_id = context.hex_trace_id  # 32-character hex string
span_id = context.hex_span_id    # 16-character hex string
```

These IDs are in W3C Trace Context format and will automatically correlate with traces sent to Last9, Datadog, Grafana, or any OTLP-compatible backend.

## Testing

A standalone test script is provided to demonstrate all 4 logging modes:

```bash
ruby test_log_modes.rb
```

This script uses mocked OpenTelemetry spans to show how each logging mode formats output, without requiring a full Rails application.

## Configuration

Each initializer checks an environment variable to determine if it should load:

```bash
# Rails Logger (default)
export LOG_CORRELATION_MODE=rails_logger

# Lograge
export LOG_CORRELATION_MODE=lograge

# Semantic Logger
export LOG_CORRELATION_MODE=semantic_logger

# JSON Formatter
export LOG_CORRELATION_MODE=json
```

## Example Output

### Mode 1: Rails Logger
```
INFO: trace_id=4bf92f3577b34da6a3ce929d0e0e4736 span_id=00f067aa0ba902b7 User login successful
```

### Mode 2: Lograge
```json
{
  "method": "GET",
  "path": "/api/users",
  "status": 200,
  "duration": 12.34,
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7"
}
```

### Mode 3: Semantic Logger
```
2024-01-15 10:30:45.123 I [12345:UsersController] {trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7"} User login successful
```

### Mode 4: JSON Formatter
```json
{"timestamp":"2024-01-15T10:30:45Z","level":"INFO","message":"User login successful","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7"}
```

## Comparison

| Feature | Rails Logger | Lograge | Semantic Logger | JSON Formatter |
|---------|--------------|---------|-----------------|----------------|
| **Setup** | ⭐ Simple | ⭐⭐ Medium | ⭐⭐⭐ Advanced | ⭐⭐ Medium |
| **Structured** | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| **Performance** | Low overhead | Low overhead | Very low | Low overhead |
| **Cloud-native** | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| **Extra gems** | None | lograge | rails_semantic_logger | None |

## Verifying in Last9

After instrumenting your Rails app:

1. Start your application with OpenTelemetry configured
2. Make requests to generate traces
3. Check logs for `trace_id` and `span_id`
4. Login to Last9 → APM → Traces
5. Find a trace and click "Logs" to see correlated log entries
6. Click a log entry to jump to its trace

## Learn More

- [Last9 Ruby on Rails Integration Guide](https://last9.io/docs/integrations/frameworks/ruby/ruby-on-rails/)
- [OpenTelemetry Ruby SDK](https://opentelemetry.io/docs/instrumentation/ruby/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)

## Complete Working Example

For a complete Rails application with log-trace correlation pre-configured, see:
- `../rails-api/` - Full Rails API example with log correlation enabled
- `../rails-api/config/initializers/log_trace_correlation.rb` - Working implementation

## License

These examples are provided for demonstration purposes as part of the Last9 OpenTelemetry examples repository.
