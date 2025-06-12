# FireLens to OpenTelemetry Collector Example

This example demonstrates how to forward logs from an ECS application container using FireLens (Fluent Bit) to an OpenTelemetry Collector sidecar, without needing a separate Fluent Bit/Fluentd container.

## Architecture

```
[App Container] --stdout--> [FireLens/Fluent Bit] --forward--> [OpenTelemetry Collector (fluentforward receiver)]
```

- **App Container**: Your main application (e.g., nginx:alpine)
- **FireLens Log Router**: Managed by AWS, configured in your ECS task definition
- **OpenTelemetry Collector**: Sidecar container, receives logs via fluentforward

## Setup Steps

1. **Add OpenTelemetry Collector as a Sidecar**
   - Add the OTEL Collector as a sidecar container in your ECS task definition.
   - Use the latest contrib image: `otel/opentelemetry-collector-contrib:latest`.
   - Mount your configuration file (e.g., `otel-collector-config.yaml`) into the container, typically at `/etc/otel-collector-config.yaml`.
   - Expose port 24224.
   - Example container definition:

```json
{
  "name": "otel-collector",
  "image": "otel/opentelemetry-collector-contrib:latest",
  "essential": false,
  "portMappings": [
    {
      "containerPort": 24224,
      "protocol": "tcp"
    }
  ],
  "command": [
    "--config=/etc/otel-collector-config.yaml"
  ],
  "mountPoints": [
    {
      "sourceVolume": "otel-config",
      "containerPath": "/etc/"
    }
  ]
}
```

- In your `volumes` section, mount the config file directory from the host:

```json
{
  "name": "otel-config",
  "host": {
    "sourcePath": "/path/to/your/config"
  }
}
```

- Place your `otel-collector-config.yaml` in `/path/to/your/config` on the host, so it is available at `/etc/otel-collector-config.yaml` inside the container.

2. **Configure FireLens in Your App Container**
   - Set the log driver to `awsfirelens`.
   - Set the destination to the OTEL Collector using `Host` and `Port` (TCP 24224).

3. **Update OTEL Collector Config**
   - Enable the `fluentforward` receiver on port 24224.
   - Configure your desired exporters. In this example, the `debug` exporter is used to print logs to the collector's output for testing and validation.
   - Example config snippet (matching the latest config):

```yaml
receivers:
  fluentforward:
    endpoint: 0.0.0.0:24224

exporters:
  debug:
    loglevel: debug

service:
  pipelines:
    logs:
      receivers: [fluentforward]
      exporters: [debug]
```

4. **No Need for Separate Fluent Bit/Fluentd Container**
   - FireLens manages Fluent Bit for you.
   - You only need your app and the OTEL Collector as containers in the task.

## Example Files

- `otel-collector-config.yaml`: OpenTelemetry Collector configuration (uses the `debug` exporter)
- `taskdefinition.json`: ECS task definition example

## References

- [project0/aws-ecs-firelens-opentelemetry](https://github.com/project0/aws-ecs-firelens-opentelemetry)
- [AWS FireLens documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_firelens.html)
- [OpenTelemetry Collector fluentforward receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/fluentforwardreceiver) 