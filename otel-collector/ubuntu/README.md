# Installing Otelcollector on Ubuntu and Collect logs from specific file

Use Levitate's OpenTelemetry endpoint to ingest logs from Ubuntu instances using Otel Collector.

## Prerequisites:

1. Install Otel Collector. There are multiple ways to install the Otel Collector. One possible way of installing it using the package is as follows. Every Collector release includes APK, DEB and RPM packaging for Linux amd64/arm64/i386 systems.
2. Tested the following configuration with Ubuntu 20.04/22.04 (LTS) versions.

```bash
sudo apt-get update
sudo apt-get -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.110.0/otelcol-contrib_0.110.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.110.0_linux_amd64.deb
```

More installation options can be found [here](https://opentelemetry.io/docs/collector/installation/).

## Sample Otel collector Configuration:

The default path for otel config is `/etc/otelcol-contrib/config.yaml`.

You can edit it and update it with the configuration below. The configuration for operators is especially important to extract the timestamp and severity.

For JSON logs, you can use json_parser and use its keys for log attributes. For non-structured logs, use the regex_parser.

The configuration provides a sample example of JSON parser.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318 

  # Detailed configuration options can be found at https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/filelogreceiver
  filelog:
    include: [/var/log/app/*.log]
    include_file_path: true
    operators:
      - type: json_parser
      - type: severity_parser
        parse_from: attributes.level
        mapping:
          critical: 50
          error: 40
          warning: 30
          info: 20
          debug: 10

processors:
  transform/add_timestamp:
    log_statements:
      - context: log
        statements:
          - set(observed_time, Now())
          - set(time, Now())
  attributes:
    actions:
      - key: test.name
        value: "jammytest"
        action: insert
      - key: deployment.environment
        value: "production"
        action: insert
      - key: otel.processed
        value: true
        action: insert
  batch:
    timeout: 1s
    send_batch_size: 1024

exporters:
  debug:
    verbosity: detailed
  otlp/last9:
    endpoint: Use Otlp endpoint from Integration page
    headers:
      "Authorization": Use Auth header details from Integrations page
    timeout: 30s

service:
  pipelines:
    logs:
      receivers: [filelog]
      processors: [attributes, batch, transform/add_timestamp]
      exporters: [debug, otlp/last9]
```

## Run the otel collector using configuration

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

## Verification

Login to Levitate and verify logs in Managed Grafana.

## Troubleshooting

Please get in touch with us on Discord [here](https://discord.com/invite/Q3p2EEucx9) or Email if you have any questions.
