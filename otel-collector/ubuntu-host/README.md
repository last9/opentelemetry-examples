# Installing OTEL Collector to scrape Ubuntu Host metrics

This guide explains how to use Levitate's OpenTelemetry metrics endpoint to ingest metrics from Ubuntu using OpenTelemetry Collector.

## Prerequisites

1. Install Otel Collector. There are multiple ways to install the Otel Collector. One possible way of installing it using the package is as follows. Every Collector release includes APK, DEB and RPM packaging for Linux amd64/arm64/i386 systems.
2. Tested the following configuration with Ubuntu 20.04/22.04 (LTS) versions.

## Installation Steps

### 1. Install OpenTelemetry Collector

Tested on Ubuntu 22.04 (LTS):

```bash
sudo apt-get update
sudo apt-get -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.110.0/otelcol-contrib_0.110.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.110.0_linux_amd64.deb
```

For more installation options, refer to the [official documentation](https://opentelemetry.io/docs/collector/installation/).

## Configuration

### OpenTelemetry Collector Configuration

Edit the configuration file at `/etc/otelcol-contrib/config.yaml`:

```yaml
receivers:
  hostmetrics:
    collection_interval: 30s
    scrapers:
      cpu:
        metrics:
          system.cpu.time:
            enabled: true
          system.cpu.utilization:
            enabled: true
          system.cpu.logical.count:
            enabled: true
      memory:
        metrics:
          system.memory.usage:
            enabled: true
          system.memory.utilization:
            enabled: true
      load:
        metrics:
          system.cpu.load_average.1m:
            enabled: true
          system.cpu.load_average.5m:
            enabled: true
          system.cpu.load_average.15m:
            enabled: true
      disk:
        metrics:
          system.disk.io:
            enabled: true
          system.disk.operations:
            enabled: true
      filesystem:
        metrics:
          system.filesystem.usage:
            enabled: true
          system.filesystem.utilization:
            enabled: true
      network:
        metrics:
          system.network.io:
            enabled: true
          system.network.packets:
            enabled: true
          system.network.errors:
            enabled: true
      paging:
        metrics:
          system.paging.usage:
            enabled: true
          system.paging.operations:
            enabled: true
      processes:
        metrics:
          system.processes.count:
            enabled: true
          system.processes.created:
            enabled: true
      process:
        mute_process_user_error: true
        metrics:
          process.cpu.time:
            enabled: true
          process.cpu.utilization:
            enabled: true
          process.memory.usage:
            enabled: true
          process.memory.utilization:
            enabled: true
          process.disk.io:
            enabled: true
          process.threads:
            enabled: true
          process.paging.faults:
            enabled: true

processors:
  batch:
    timeout: 5s
    send_batch_size: 10000
    send_batch_max_size: 10000
  resourcedetection/system:
    detectors: ["system"]
    system:
      hostname_sources: ["os"]
  transform/hostmetrics:
    metric_statements:
      - context: datapoint
        statements:
          - set(attributes["host.name"], resource.attributes["host.name"])
          - set(attributes["process.command"], resource.attributes["process.command"])
          - set(attributes["process.command_line"], resource.attributes["process.command_line"])
          - set(attributes["process.executable.name"], resource.attributes["process.executable.name"])
          - set(attributes["process.executable.path"], resource.attributes["process.executable.path"])
          - set(attributes["process.owner"], resource.attributes["process.owner"])
          - set(attributes["process.parent_pid"], resource.attributes["process.parent_pid"])
          - set(attributes["process.pid"], resource.attributes["process.pid"])

exporters:
  debug:
    verbosity: detailed
  otlp/last9:
    endpoint: <last9_otlp_endpoint>
    headers:
      Authorization: <last9_auth_header>


service:
  pipelines:
    metrics:
      receivers: [hostmetrics]
      processors: [resourcedetection/system, transform/hostmetrics, batch]
      exporters: [debug, otlp/last9]
```



Run the OpenTelemetry Collector:

```bash
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Run the otel collector using `systemctl` command

```bash
sudo systemctl start otelcol-contrib
sudo systemctl status otelcol-contrib
sudo systemctl restart otelcol-contrib
```

## Checking logs of otel collector

```bash
sudo journalctl -u otelcol-contrib -f
```

## Verifying Metrics

This will push the metrics from YACE config to be sent to Levitate. To see the data in action, visit the [Grafana Dashboard](https://app.last9.io/).

## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
