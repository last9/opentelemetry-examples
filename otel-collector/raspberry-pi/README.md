# Monitoring Raspberry Pi with OpenTelemetry Collector

Monitor your Raspberry Pi system metrics (CPU, memory, disk, network, temperature) using the OpenTelemetry Collector and send them to Last9.

## Prerequisites

- Raspberry Pi (any model) running Raspberry Pi OS (32-bit or 64-bit)
- SSH access to your Pi
- Last9 account with OTLP endpoint credentials

## Quick Start

### 1. Determine Your Pi's Architecture

```bash
uname -m
```

- `armv7l` → 32-bit (use `linux_arm` package)
- `aarch64` → 64-bit (use `linux_arm64` package)

### 2. Install OpenTelemetry Collector

**For 64-bit (arm64):**
```bash
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.96.0/otelcol-contrib_0.96.0_linux_arm64.deb
sudo dpkg -i otelcol-contrib_0.96.0_linux_arm64.deb
```

**For 32-bit (armv7):**
```bash
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.96.0/otelcol-contrib_0.96.0_linux_arm.deb
sudo dpkg -i otelcol-contrib_0.96.0_linux_arm.deb
```

### 3. Configure the Collector

Copy the configuration file:
```bash
sudo cp otel-config.yaml /etc/otelcol-contrib/config.yaml
```

Edit with your Last9 credentials:
```bash
sudo nano /etc/otelcol-contrib/config.yaml
```

Replace:
- `<last9_otlp_endpoint>` → Your Last9 OTLP endpoint (e.g., `otlp.last9.io:443`)
- `<last9_auth_header>` → Your Last9 auth header (e.g., `Basic <base64-encoded-credentials>`)

### 4. Start the Collector

```bash
sudo systemctl enable otelcol-contrib
sudo systemctl start otelcol-contrib
```

## Configuration

| Environment Variable | Description | Example |
|---------------------|-------------|---------|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP gRPC endpoint | `otlp.last9.io:443` |
| `LAST9_AUTH_HEADER` | Authorization header | `Basic dXNlcjpwYXNz` |

## Collected Metrics

The configuration collects:

| Category | Metrics |
|----------|---------|
| CPU | Usage per core, load averages |
| Memory | Used, free, cached, buffers |
| Disk | Usage, I/O operations, read/write bytes |
| Filesystem | Usage per mount point |
| Network | Bytes sent/received, packets, errors |
| Load | 1m, 5m, 15m averages |
| Process | Count, states |

### Pi-Specific: CPU Temperature

The `hostmetrics` receiver does not natively collect Raspberry Pi temperature. To add it, use a custom script with the `filestats` receiver (see Advanced Configuration below).

## Verification

Check collector status:
```bash
sudo systemctl status otelcol-contrib
```

View logs:
```bash
sudo journalctl -u otelcol-contrib -f
```

Test locally with debug output:
```bash
sudo otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

Metrics should appear in your [Last9 dashboard](https://app.last9.io/) within a few minutes.

## Advanced Configuration

<details>
<summary>Add CPU Temperature Monitoring</summary>

Create a script to expose temperature as a metric:

```bash
# /usr/local/bin/pi-temp-exporter.sh
#!/bin/bash
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
echo "pi_cpu_temperature_celsius $(echo "scale=2; $TEMP/1000" | bc)"
```

Add to crontab to write to a file, then use `filestats` receiver.

</details>

<details>
<summary>Reduce Resource Usage</summary>

For Pi Zero or older models, increase collection intervals:

```yaml
receivers:
  hostmetrics:
    collection_interval: 60s  # Instead of 30s
```

</details>

## Troubleshooting

**Collector won't start:**
```bash
sudo otelcol-contrib --config /etc/otelcol-contrib/config.yaml 2>&1 | head -50
```

**Permission errors:**
Ensure the collector can read system stats:
```bash
sudo usermod -aG adm otelcol-contrib
```

**High memory usage:**
Use the core collector instead of contrib, or increase batch timeout.

For additional help, contact us on [Discord](https://discord.gg/last9) or via email.
