# Logstash + OpenTelemetry Collector Example

This project demonstrates how to use Logstash to generate and forward logs to the OpenTelemetry Collector, which then exports them to a Last9 OTLP endpoint.

## Components
- **Logstash**: Generates log messages and forwards them via TCP.
- **OpenTelemetry Collector**: Receives logs from Logstash and exports them to Last9 (or prints them for debugging).

## Files
- `logstash.conf`: Logstash pipeline configuration.
- `otel-collector-config.yaml`: OpenTelemetry Collector configuration.
- `docker-compose.yml`: Orchestrates Logstash and the Collector with Docker.

## Prerequisites
- Docker and Docker Compose installed
- Last9 OTLP endpoint and authorization header

## Setup

> **Note:** If both Logstash and the OpenTelemetry Collector are running on the same host (e.g., the same EC2 instance or your local machine), set the `host` in the Logstash output section to `localhost` or `127.0.0.1`:
>
> ```conf
> output {
>   tcp {
>     codec => json_lines
>     host => "localhost"
>     port => 2255
>   }
> }
> ```

### 1. Configure Last9 OTLP Exporter
Edit `otel-collector-config.yaml` and set your Last9 OTLP endpoint and authorization header:

```yaml
  otlp/last9:
    endpoint: "<your-last9-otlp-endpoint>"
    headers:
      Authorization: "<your-last9-otlp-authorization-header>"
    tls:
      insecure: true
```

If you only want to debug locally, you can use the `debug` exporter instead.

### 2. Start the Stack
Run the following command:

```sh
docker-compose up --build
```

- Logstash will generate a log message every 10 seconds and send it to the OpenTelemetry Collector via TCP (port 2255).
- The Collector will forward logs to Last9 (or print them if using the debug exporter).

### 3. Customizing Log Generation
- To change the log message or interval, edit `logstash.conf`:
  - `message` sets the log content.

### 4. Stopping the Stack
To stop the containers:

```sh
docker-compose down
```

## Notes
- If running on ARM (e.g., Apple Silicon), the Docker Compose file is set to use the correct platform for Logstash.
- If running both services on the same host, they communicate via `localhost` and port `2255`.
- Ensure your EC2 security group allows inbound traffic on port 2255 if running across hosts.

## Troubleshooting
- If Logstash exits immediately, ensure the input plugin is persistent (the provided config uses a generator with an interval).
- Check container logs for errors:
  ```sh
  docker-compose logs logstash
  docker-compose logs otel-collector
  ```