# HAProxy Combined Log Splitting with OpenTelemetry Collector

## ⚠️ Important Version Note

This repository contains solutions for **two different scenarios**:

1. **OTel Collector v0.137.0+** - Can use the new **unroll processor** for OTLP-based splitting
2. **OTel Collector v0.103 and earlier** - Must use **filelog receiver** with multiline pattern

**👉 If you're using v0.103 at Last9, see [SOLUTION_FOR_V0103.md](./SOLUTION_FOR_V0103.md)**

## Problem Statement

This example demonstrates how to split HAProxy logs that are incorrectly combined into single records. The issue occurs when multiple log entries with different timestamps are written simultaneously and are not properly separated by the log collector.

**Example Combined Log (single record)**:
```
2025-12-14T02:23:07.305817+00:00 ip-192-168-6-48 haproxy[927]: [WARNING]  (927) : Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed, code: 200, check duration: 10ms. 8 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
2025-12-14T02:23:07.305939+00:00 ip-192-168-6-48 haproxy[927]: Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed, code: 200, check duration: 10ms. 8 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
```

These should be **two separate records** (note different timestamps: `.305817` vs `.305939`).

## Solution Architecture

### Components

1. **Log Generator**: Simulates HAProxy logs with combined entries
2. **OpenTelemetry Collector**: Splits logs using multiline pattern matching
3. **Debug Exporter**: Outputs separated logs to stdout

### How It Works

The OpenTelemetry Collector's `filelog` receiver uses the `multiline.line_start_pattern` configuration to detect log boundaries based on RFC3339 timestamp patterns. When a line starts with a timestamp matching the pattern, it's treated as a new log entry.

**Key Pattern**: `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}\+\d{2}:\d{2}`

This pattern matches RFC3339 timestamps with microsecond precision at the start of each line.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Sufficient disk space for logs (~100MB)

### Running the Example

1. **Start all services**:
   ```bash
   docker compose up -d
   ```

2. **View generated logs** (combined entries in file):
   ```bash
   docker logs -f haproxy-log-generator
   ```

3. **View collector output** (split logs):
   ```bash
   docker logs -f otel-collector-haproxy
   ```

4. **Check raw log file**:
   ```bash
   cat logs/haproxy.log
   ```

5. **Stop services**:
   ```bash
   docker compose down
   ```

### Expected Output

**Before (Raw Log File - Combined)**:
```
2025-12-14T02:23:07.305817+00:00 ip-192-168-6-48 haproxy[927]: [WARNING] Server is UP
2025-12-14T02:23:07.305939+00:00 ip-192-168-6-48 haproxy[927]: Server check passed
2025-12-14T02:23:08.412653+00:00 ip-192-168-6-48 haproxy[927]: [INFO] Backend available
```

**After (Collector Output - Split into Separate Records)**:
```
LogRecord #0
Timestamp: 2025-12-14 02:23:07.305817 +0000 UTC
SeverityText: WARNING
Body: Str([WARNING] Server is UP)
Attributes:
     -> log.file.name: Str(haproxy.log)
     -> log.file.path: Str(/logs/haproxy.log)
     -> service.name: Str(haproxy)
     -> process: Str(haproxy)
     -> pid: Str(927)
     -> message: Str([WARNING] Server is UP)
Resource:
     -> hostname: Str(ip-192-168-6-48)

LogRecord #1
Timestamp: 2025-12-14 02:23:07.305939 +0000 UTC
Body: Str(Server check passed)
Attributes:
     -> log.file.name: Str(haproxy.log)
     -> log.file.path: Str(/logs/haproxy.log)
     -> service.name: Str(haproxy)
     -> process: Str(haproxy)
     -> pid: Str(927)
     -> message: Str(Server check passed)
Resource:
     -> hostname: Str(ip-192-168-6-48)

LogRecord #2
Timestamp: 2025-12-14 02:23:08.412653 +0000 UTC
SeverityText: INFO
Body: Str([INFO] Backend available)
Attributes:
     -> log.file.name: Str(haproxy.log)
     -> log.file.path: Str(/logs/haproxy.log)
     -> service.name: Str(haproxy)
     -> process: Str(haproxy)
     -> pid: Str(927)
     -> message: Str([INFO] Backend available)
Resource:
     -> hostname: Str(ip-192-168-6-48)
```

## Configuration Deep-Dive

### Multiline Pattern Configuration

The core of the solution is in `otel-collector-config.yaml`:

```yaml
receivers:
  filelog/haproxy:
    multiline:
      line_start_pattern: '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}\+\d{2}:\d{2}'
```

**Pattern Breakdown**:
- `^` - Matches start of line (critical for detecting boundaries)
- `\d{4}-\d{2}-\d{2}` - Matches date (YYYY-MM-DD)
- `T` - Literal 'T' separator
- `\d{2}:\d{2}:\d{2}` - Matches time (HH:MM:SS)
- `\.` - Literal dot
- `\d{6}` - Matches microseconds (6 digits)
- `\+` - Literal plus sign
- `\d{2}:\d{2}` - Matches timezone offset (±00:00)

### Parsing Pipeline

After splitting, the collector applies several operators:

1. **Regex Parser**: Extracts structured fields from HAProxy syslog format
   - timestamp
   - hostname
   - process name
   - process ID (PID)
   - message

2. **Severity Extraction**: Parses severity from message brackets (`[WARNING]`, `[ERROR]`, `[INFO]`)

3. **Attribute Enrichment**: Adds service name and log source metadata

4. **Resource Attribution**: Moves hostname to resource attributes

### HAProxy Log Format

This example handles the standard HAProxy syslog format:
```
TIMESTAMP HOSTNAME PROCESS[PID]: MESSAGE
```

Example:
```
2025-12-14T02:23:07.305817+00:00 ip-192-168-6-48 haproxy[927]: [WARNING] Server is UP
```

## Testing and Verification

### Verification Commands

```bash
# Count lines in source file
wc -l logs/haproxy.log

# Count LogRecords in collector output
docker logs otel-collector-haproxy 2>&1 | grep -c "LogRecord #"

# View specific parsed fields
docker logs otel-collector-haproxy 2>&1 | grep "Timestamp:"

# Check for parsing errors
docker logs otel-collector-haproxy 2>&1 | grep -i error

# View raw log file content
docker exec haproxy-log-generator cat /logs/haproxy.log

# Check collector can access log file
docker exec otel-collector-haproxy ls -la /logs/
```

### Success Criteria

✓ Number of LogRecords equals number of lines in `haproxy.log`
✓ Each LogRecord has unique timestamp
✓ Timestamps preserved with microsecond precision
✓ Attributes properly extracted (hostname, process, pid)
✓ Severity correctly parsed from message (WARNING, ERROR, INFO)

### Testing Different Scenarios

1. **Single Entry**: Stop generator, manually add one line
   ```bash
   docker compose stop log-generator
   echo "2025-12-14T10:00:00.123456+00:00 ip-192-168-6-48 haproxy[927]: [INFO] Test log" >> logs/haproxy.log
   ```

2. **Burst Entries**: Generator writes 3 entries simultaneously every 10 seconds

3. **Manual Batch**: Add many entries at once
   ```bash
   for i in {1..10}; do
     echo "$(date -u +%Y-%m-%dT%H:%M:%S.%6N)+00:00 ip-192-168-6-48 haproxy[927]: Test log $i" >> logs/haproxy.log
   done
   ```

## Troubleshooting

### Logs Not Splitting

**Issue**: All logs appear as single combined entry

**Solutions**:
1. **Check pattern syntax**: Ensure backslashes are properly escaped (`\d` not `d`)
   ```bash
   # View collector config
   docker exec otel-collector-haproxy cat /etc/otel-collector/config.yaml | grep line_start_pattern
   ```

2. **Verify timestamp format**: Ensure logs match the pattern exactly
   ```bash
   # Check log file format
   head -1 logs/haproxy.log
   ```

3. **Restart collector**: Pattern changes require restart
   ```bash
   docker compose restart otel-collector
   ```

### Collector Not Reading Logs

**Issue**: No LogRecords in output

**Solutions**:
1. **Verify file exists and is readable**:
   ```bash
   docker exec otel-collector-haproxy ls -la /logs/
   docker exec otel-collector-haproxy cat /logs/haproxy.log
   ```

2. **Check collector logs for errors**:
   ```bash
   docker logs otel-collector-haproxy 2>&1 | tail -50
   ```

3. **Ensure generator is running**:
   ```bash
   docker ps | grep haproxy-log-generator
   docker logs haproxy-log-generator
   ```

### Duplicate Logs on Restart

**Issue**: Logs reprocessed when collector restarts (because `start_at: beginning`)

**Solution**: For production, use `start_at: end` and add file_storage extension (see Production Considerations)

### Parsing Errors

**Issue**: Attributes not extracted correctly

**Solutions**:
1. **Check regex pattern**: Verify it matches your log format
2. **Test regex**: Use online regex tester with sample log line
3. **View unparsed logs**: Check Body field for raw content

## Production Considerations

### 1. Checkpointing (Critical for Production)

Add file storage extension to prevent reprocessing logs on restart:

```yaml
extensions:
  file_storage:
    directory: /var/lib/otelcol/file_storage

receivers:
  filelog/haproxy:
    storage: file_storage  # Link to storage extension
    # ... rest of config
```

**Update service configuration**:
```yaml
service:
  extensions: [file_storage]
  pipelines:
    logs:
      # ... rest of config
```

### 2. Start Position

```yaml
receivers:
  filelog/haproxy:
    # Development/Testing: Read from beginning
    start_at: beginning

    # Production: Only read new logs
    start_at: end
```

### 3. Log Rotation Handling

Handle HAProxy log rotation (e.g., `haproxy.log.1`, `haproxy.log.2`):

```yaml
receivers:
  filelog/haproxy:
    include:
      - /logs/haproxy*.log
    force_flush_period: 5s
```

### 4. Performance Tuning

Adjust based on log volume:

```yaml
processors:
  batch:
    timeout: 5s
    send_batch_size: 1000  # Increase for high volume

  memory_limiter:
    limit_percentage: 85
    spike_limit_percentage: 15
```

### 5. Export to Last9 (or other backends)

Replace debug exporter with OTLP:

```yaml
exporters:
  otlp/last9:
    endpoint: "${LAST9_OTLP_ENDPOINT}"
    headers:
      Authorization: "Basic ${LAST9_AUTH_TOKEN}"
    compression: gzip

service:
  pipelines:
    logs:
      receivers: [filelog/haproxy]
      processors: [memory_limiter, resourcedetection/system, batch]
      exporters: [otlp/last9]  # Change from debug to otlp/last9
```

**Environment variables**:
```yaml
# docker-compose.yaml
services:
  otel-collector:
    environment:
      - LAST9_OTLP_ENDPOINT=https://otlp.last9.io
      - LAST9_AUTH_TOKEN=your-token-here
```

## Adapting for Your Environment

### Different Timestamp Format

If your HAProxy uses a different timestamp format, adjust the pattern:

**Example 1**: Format without timezone: `2025-12-14 02:23:07.305817`
```yaml
multiline:
  line_start_pattern: '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}'
```

**Example 2**: Format with milliseconds: `2025-12-14T02:23:07.305+00:00`
```yaml
multiline:
  line_start_pattern: '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}\+\d{2}:\d{2}'
```

### Different Log Structure

Modify the regex parser to match your log format:

```yaml
operators:
  - type: regex_parser
    regex: '^(?P<timestamp>...) (?P<custom_field>...) (?P<message>.*)$'
```

### Additional Fields

Add more attributes or processing:

```yaml
operators:
  # Extract backend name from message
  - type: regex_parser
    regex: 'backend (?P<backend_name>[\w-]+)'
    parse_from: attributes.message
    if: 'attributes.message matches "backend"'
```

## Architecture Diagram

```
┌─────────────────┐
│  Log Generator  │
│    (bash:5.2)   │
│                 │
│ Writes combined │
│  HAProxy logs   │
└────────┬────────┘
         │
         │ /logs/haproxy.log
         │ (shared volume)
         │
         ▼
┌─────────────────────────────────┐
│   OpenTelemetry Collector       │
│   (otel/contrib:0.128.0)        │
│                                 │
│ ┌─────────────────────────┐    │
│ │  filelog receiver       │    │
│ │  - Reads log file       │    │
│ │  - Splits by timestamp  │    │
│ │  - Parses HAProxy fmt   │    │
│ └───────────┬─────────────┘    │
│             │                   │
│             ▼                   │
│ ┌─────────────────────────┐    │
│ │  Processors             │    │
│ │  - memory_limiter       │    │
│ │  - resourcedetection    │    │
│ │  - batch                │    │
│ └───────────┬─────────────┘    │
│             │                   │
│             ▼                   │
│ ┌─────────────────────────┐    │
│ │  debug exporter         │    │
│ │  (outputs to stdout)    │    │
│ └─────────────────────────┘    │
└─────────────────────────────────┘
         │
         ▼
   docker logs output
   (separate LogRecords)
```

## Related Examples

- **Multiline Log Aggregation**: [datadog-k8s-operator/migration-examples/06-multiline-logs](../../datadog-k8s-operator/migration-examples/06-multiline-logs/)
- **Fluent Bit Integration**: [../fluent-bit](../fluent-bit/)
- **Logstash Integration**: [../logstash](../logstash/)

## Additional Documentation

- **[Standard Patterns Guide](./STANDARD_PATTERNS.md)**: Comprehensive multiline patterns for Java, Node.js, Python, Go, Ruby, Nginx, HAProxy, databases, and more
- **[Why This Happens](./WHY_THIS_HAPPENS.md)**: Root cause analysis of log combining/splitting issues
- **[Solution for v0.103](./SOLUTION_FOR_V0103.md)**: Specific guidance for OpenTelemetry Collector v0.103

## References

- [OpenTelemetry Filelog Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/filelogreceiver)
- [Multiline Configuration Guide](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/file_input.md)
- [Stanza Operators Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/docs/operators/README.md)
- [Last9 OpenTelemetry Filelog Guide](https://last9.io/blog/opentelemetry-filelog-receiver-kubernetes-log-collection/)

## License

This example is part of the Last9 OpenTelemetry examples repository.
