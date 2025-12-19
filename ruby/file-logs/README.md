# Ruby File Logs with OpenTelemetry Collector

A simple example showing how to collect Ruby application logs written to a file using the OpenTelemetry Collector Contrib's filelog receiver.

## Overview

This example demonstrates:
- A Ruby application that writes JSON-formatted logs to a file
- OpenTelemetry Collector configuration to read and parse those logs
- Sending the collected logs to an observability backend

## Prerequisites

- Ruby installed (any recent version)
- OpenTelemetry Collector Contrib installed

## Quick Start

### 1. Start the Ruby Application

The application writes logs to `logs/application.log`:

```bash
cd ruby/file-logs
ruby app.rb
```

The application will:
- Create a `logs/` directory if it doesn't exist
- Write JSON-formatted logs with different severity levels (INFO, WARN, ERROR)
- Generate log entries every 2 seconds
- Run until you press Ctrl+C

### 2. Install OpenTelemetry Collector Contrib

```bash
# Linux
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.110.0/otelcol-contrib_0.110.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.110.0_linux_amd64.deb

# macOS
brew install opentelemetry-collector-contrib
```

### 3. Configure the Collector

Update `otel-config.yaml`:

1. Replace the file path in the `filelog` receiver:
   ```yaml
   include: [/absolute/path/to/ruby/file-logs/logs/*.log]
   ```

2. Configure your exporter (optional):
   ```yaml
   exporters:
     otlp:
       endpoint: "<YOUR_OTEL_ENDPOINT>"
       headers:
         "Authorization": "Basic <YOUR_AUTH_TOKEN>"
   ```

### 4. Run the Collector

```bash
otelcol-contrib --config otel-config.yaml
```

The collector will:
- Read logs from the Ruby application's log file
- Parse the JSON format
- Extract timestamp, log level, message, and service name
- Export logs to the configured backend (or print to console with debug exporter)

## Log Format

The Ruby application writes JSON logs in this format:

```json
{
  "timestamp": "2025-12-19T15:30:45+00:00",
  "level": "INFO",
  "message": "User request processed successfully - Request ID: 1234",
  "service": "ruby-app"
}
```

## Configuration Details

### Filelog Receiver

The collector uses the `filelog` receiver to:
- Monitor log files matching the pattern `logs/*.log`
- Parse JSON-formatted log entries
- Extract structured fields (timestamp, level, message, service)
- Map fields to OpenTelemetry semantic conventions

### Key Features

- **JSON Parsing**: Automatically parses JSON log entries
- **Timestamp Extraction**: Uses the log's timestamp field
- **Log Level Mapping**: Maps severity levels to `log.level` attribute
- **Service Name**: Extracts service name to resource attributes
- **File Tracking**: Includes file path and name in the logs

## Troubleshooting

1. **Logs not appearing**: Verify the file path in `otel-config.yaml` is absolute and correct
2. **Permission errors**: Ensure the collector has read permissions for the log directory
3. **No output**: Check the collector is running and the Ruby app is generating logs

### Verify Setup

Check if logs are being written:
```bash
tail -f logs/application.log
```

Check collector status:
```bash
# If running as systemd service
sudo systemctl status otelcol-contrib
sudo journalctl -u otelcol-contrib -f
```

## Customization

### Change Log Format

Modify the logger formatter in `app.rb`:

```ruby
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime} [#{severity}] #{msg}\n"  # Plain text format
end
```

Then update the collector's operators to match (remove `json_parser` for plain text).

### Add More Attributes

Add custom fields to the log JSON:

```ruby
{
  timestamp: datetime.iso8601,
  level: severity,
  message: msg,
  service: 'ruby-app',
  environment: 'production',  # Add custom field
  host: Socket.gethostname     # Add hostname
}.to_json + "\n"
```

## Next Steps

- Configure exporters to send logs to your observability platform
- Add filtering or transformation processors
- Set up log-based alerting in your backend
- Correlate logs with traces and metrics using trace/span IDs
