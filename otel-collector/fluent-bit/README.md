# Fluent Bit to OpenTelemetry Collector Integration

This project demonstrates how to configure Fluent Bit to send log data to an OpenTelemetry Collector using Docker Compose.

## Project Structure

- `otel-collector/fluent-bit/fluent-bit.conf`: Configuration file for Fluent Bit
- `otel-collector/fluent-bit/otel-config.yaml`: Configuration file for OpenTelemetry Collector
- `otel-collector/fluent-bit/docker-compose.yaml`: Docker Compose file for running the services

## Fluent Bit Configuration

The Fluent Bit configuration (`fluent-bit.conf`) is set up to:

- Flush logs every 5 seconds
- Run in the foreground
- Use INFO log level
- Enable HTTP server on port 2020
- Generate dummy log messages
- Output logs to OpenTelemetry Collector

Key components:

```ini
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info
    HTTP_Server  On
    HTTP_Listen  0.0.0.0
    HTTP_Port    2020

[INPUT]
    Name            dummy
    Dummy           {"message": "custom dummy"}
    Tag             dummy.log    
    Rate            1

[OUTPUT]
    Name        opentelemetry
    Match       *
    Host        ${FLUENT_OTLP_HOST}
    Port        ${FLUENT_OTLP_PORT}
    Logs_uri    /v1/logs
    logs_body_key_attributes true
    Header     X-Logging-Host last9.local
    Header     X-Logging-Name local-app
    Header     X-Logging-Env staging
```

## OpenTelemetry Collector Configuration

The OpenTelemetry Collector configuration (`otel-config.yaml`) is set up to:

- Receive OTLP data via gRPC and HTTP
- Process data using memory limiter, batch, and resource processors
- Export data using the debug exporter

Key components:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        include_metadata: true
      http:
        include_metadata: true

processors:
  memory_limiter:
    check_interval: 5s
    limit_percentage: 85
    spike_limit_percentage: 15
  batch:
    timeout: 5s
    send_batch_size: 100000
  resource:
    attributes:
    - key: host
      from_context: X-Logging-Host
      action: insert
    - key: service.name
      from_context: X-Logging-Name
      action: insert
    - key: deployment.environment
      from_context: X-Logging-Env
      action: insert

exporters:
  debug:
    verbosity: detailed

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [debug]
```

## Docker Compose Setup

The `docker-compose.yaml` file defines two services:

1. OpenTelemetry Collector
2. Fluent Bit

### OpenTelemetry Collector Service

```yaml
otel-collector:
  image: otel/opentelemetry-collector-contrib:0.103.0
  container_name: otel-collector
  ports:
    - "4317:4317"   # for OTLP/gRPC
    - "4318:4318"   # for OTLP/HTTP
  volumes:
    - ./otel-config.yaml:/etc/otel-collector/config.yaml
  command: ["--config", "/etc/otel-collector/config.yaml"]
  restart: unless-stopped
```

### Fluent Bit Service

```yaml
fluent-bit:
  image: fluent/fluent-bit:3.1.4
  container_name: fluent-bit
  volumes:
    - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
```

## Setup and Running

1. Install Fluent Bit and OpenTelemetry Collector on your system.

2. Set the following environment variables:
   ```bash
   export FLUENT_OTLP_HOST=<otel-collector-host>
   export FLUENT_OTLP_PORT=<otel-collector-port>
   ```

3. Start the OpenTelemetry Collector and Fluent Bit using Docker Compose:
   ```bash
   docker compose up -d
   ```

## Verifying the Setup

1. Check the Fluent Bit logs to ensure it's generating dummy logs and sending them to the OpenTelemetry Collector.

2. Examine the OpenTelemetry Collector's debug output to verify that it's receiving and processing the logs from Fluent Bit.

3. The debug exporter in the OpenTelemetry Collector configuration will print detailed information about the received logs.

## Customization

- Modify the `[INPUT]` section in `fluent-bit.conf` to collect logs from your desired sources instead of using dummy data.
- Adjust the `[OUTPUT]` section to change the headers or other parameters as needed for your specific use case.
- Update the `processors` and `exporters` in `otel-config.yaml` to transform the data or send it to your preferred destination such as [Last9](https://last9.io).