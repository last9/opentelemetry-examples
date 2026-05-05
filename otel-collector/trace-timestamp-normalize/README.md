# Trace Timestamp Normalization

Demonstrates an OpenTelemetry Collector pipeline that detects spans with bogus start/end timestamps (far past or far future) and rewrites them to the current ingestion time while preserving the span's duration. The original timestamps are stashed as attributes for forensics.

This is useful when client SDKs intermittently emit spans with broken clocks (e.g., timestamps in year 2081), which would otherwise be rejected by downstream storage or land in the wrong time bucket.

## How it works

The `transform/old_traces` processor:

1. Detects spans where `start_time` is more than 900 seconds away from `Now()` (past or future).
2. Saves the original `start_time` and `end_time` as attributes (`l9.original_start_time`, `l9.original_end_time`).
3. Rewrites `end_time = Now() + (end_time - start_time)` first to preserve the span's duration.
4. Rewrites `start_time = Now()`.

Spans within the 900s window pass through untouched.

## Prerequisites

- Docker + Docker Compose
- `curl`, `openssl`

## Quick Start

1. Start the collector:

   ```bash
   docker compose up -d
   ```

2. In another terminal, tail the collector logs:

   ```bash
   docker compose logs -f otel-collector
   ```

3. Send a span with timestamps set to year 2081:

   ```bash
   ./send-bad-span.sh
   ```

4. In the logs, look for the span. The `Start time` and `End time` should be the current time (not year 2081), and the attributes should include:

   ```
   -> l9.original_start_time: Int(3502915200)
   -> l9.original_end_time: Int(3502915201)
   ```

5. Stop the collector:

   ```bash
   docker compose down
   ```

## Configuration

| File | Purpose |
|------|---------|
| `otel-collector-config.yaml` | Collector pipeline with `transform/old_traces` and a debug exporter |
| `docker-compose.yaml` | Runs `otel/opentelemetry-collector-contrib:0.144.0` |
| `send-bad-span.sh` | Sends a single OTLP/HTTP span with timestamps in year 2081 |

### Tuning the threshold

The 900-second window matches Last9's logs guard. To make it stricter, edit the condition in `otel-collector-config.yaml`:

```yaml
conditions:
  - (UnixSeconds(Now()) - UnixSeconds(start_time) > 300 or UnixSeconds(start_time) - UnixSeconds(Now()) > 300)
```

### Dropping instead of normalizing

If you would rather drop bad spans, replace the `transform/old_traces` processor with a `filter` processor:

```yaml
filter/bad_span_timestamps:
  error_mode: ignore
  traces:
    span:
      - UnixSeconds(start_time) - UnixSeconds(Now()) > 86400
      - UnixSeconds(Now()) - UnixSeconds(start_time) > 86400
```

## Verification

To confirm a normal-timestamp span is *not* modified, edit `send-bad-span.sh` and replace `START_NS` / `END_NS` with the current time in nanoseconds:

```bash
START_NS=$(($(date +%s) * 1000000000))
END_NS=$(( START_NS + 1000000000 ))
```

The span should appear in the logs without `l9.original_*` attributes.
