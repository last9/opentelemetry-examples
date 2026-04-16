# Fluent Bit 2.x to Last9 via OpenTelemetry Collector

Send logs from Fluent Bit 2.x to Last9 using an OTel Collector. The collector adds OTLP resource attributes (`service.name`, `deployment.environment`) that Fluent Bit 2.x cannot set for logs on its own.

## Prerequisites

- Docker and Docker Compose
- Last9 account with OTLP endpoint credentials

## Quick Start

1. Copy the environment template and fill in your Last9 credentials:

```bash
cp .env.example .env
# Edit .env with your Last9 host and base64-encoded credentials
```

To generate the base64 auth value:

```bash
echo -n "username:password" | base64
```

2. Start the stack:

```bash
docker compose up
```

This starts three containers:
- **app** — generates JSON log lines every second
- **fluent-bit** — collects logs via Docker fluentd driver, forwards to collector
- **otel-collector** — adds resource attributes, exports to Last9

## Configuration

| File | Purpose |
|------|---------|
| `fluent-bit.conf` | Forward input, JSON parser filter, record modifier, OTel output to collector |
| `otel-config.yaml` | OTLP receiver, resource processor (service.name etc.), otlphttp exporter to Last9 |
| `.env` | `LAST9_HOST` and `LAST9_AUTH` for the collector's exporter |

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `LAST9_HOST` | Last9 OTLP ingest hostname | `otlp.example.last9.io` |
| `LAST9_AUTH` | Base64 of `username:password` | `dXNlcjpwYXNz` |

## Verification

Check the OTel Collector debug output for resource attributes:

```bash
docker logs otel-collector 2>&1 | grep -A3 "Resource attributes"
```

Expected output:

```
Resource attributes:
     -> service.name: Str(fluent-bit-example)
     -> deployment.environment: Str(dev)
     -> k8s.cluster.name: Str(local-test)
```

Check Fluent Bit stdout for parsed log records:

```bash
docker logs fluent-bit 2>&1 | grep "message"
```

Then verify logs appear in [Last9 Logs Explorer](https://app.last9.io/logs) with the correct service name.

<details>
<summary>Why OTel Collector is required for Fluent Bit 2.x</summary>

Fluent Bit 2.x's `add_label` directive in the OpenTelemetry output only sets resource attributes for **metrics**, not logs. The `record_modifier` filter adds fields to the log record body, but not to the OTLP Resource level where Last9 reads `service.name`.

The OTel Collector's `resource` processor properly sets OTLP Resource attributes for all signal types. Fluent Bit 3.x+ supports `logs_body_key_attributes` which can handle this directly without a collector.

</details>
