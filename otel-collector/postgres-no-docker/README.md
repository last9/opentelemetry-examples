# PostgreSQL + OTel Collector (No Docker)

Collects PostgreSQL metrics and slow query logs using the OTel Collector binary — no Docker required. Runs as a systemd service on the same host as PostgreSQL.

## Prerequisites

- PostgreSQL 14+ installed and running
- OTel Collector binary installed
- Last9 OTLP credentials

## PostgreSQL Configuration

1. Create a monitoring user:

   ```sql
   CREATE USER otel WITH PASSWORD 'your_secure_password';
   GRANT pg_monitor TO otel;
   ```

2. Enable slow query logging in `postgresql.conf`:

   ```ini
   log_min_duration_statement = 1000   # log queries slower than 1s (in ms)
   log_line_prefix = '%t [%p] %u@%d '
   logging_collector = on
   log_directory = '/var/log/postgresql'
   log_filename = 'postgresql-%Y-%m-%d.log'
   ```

3. Reload PostgreSQL:

   ```bash
   sudo systemctl reload postgresql
   ```

## Install OTel Collector

```bash
# AMD64 (Debian/Ubuntu)
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.144.0_linux_amd64.deb

# ARM64 (Debian/Ubuntu)
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_arm64.deb
sudo dpkg -i otelcol-contrib_0.144.0_linux_arm64.deb

# RHEL/CentOS AMD64
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_amd64.rpm
sudo rpm -ivh otelcol-contrib_0.144.0_linux_amd64.rpm
```

## Quick Start

1. Copy `.env.example` to `.env` and fill in credentials:

   ```bash
   cp .env.example .env
   ```

2. Copy the collector config:

   ```bash
   sudo cp otel-collector-config.yaml /etc/otelcol-contrib/config.yaml
   ```

3. Set environment variables for the service. Edit `/etc/otelcol-contrib/otelcol-contrib.env` (created by the .deb/.rpm package) and add:

   ```bash
   OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-aps1.last9.io:443
   OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION=Basic <base64_credentials>
   POSTGRESQL_PASSWORD=<your_monitoring_user_password>
   ```

4. Grant the collector read access to PostgreSQL logs:

   ```bash
   sudo usermod -aG adm otelcol-contrib
   # or explicitly:
   sudo chmod o+r /var/log/postgresql/*.log
   ```

5. Start and enable the service:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable otelcol-contrib
   sudo systemctl start otelcol-contrib
   ```

## Verification

```bash
# Check service status
sudo systemctl status otelcol-contrib

# Watch logs
sudo journalctl -u otelcol-contrib -f
```

## Configuration

| Variable | Description |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION` | Last9 Basic auth header |
| `POSTGRESQL_PASSWORD` | Password for the `otel` monitoring user |

## Log Path

Adjust `include` in `otel-collector-config.yaml` to match your system:

| OS | Default log path |
|---|---|
| Ubuntu/Debian | `/var/log/postgresql/postgresql-*.log` |
| RHEL/CentOS | `/var/lib/pgsql/<version>/data/log/postgresql-*.log` |
| Custom | Set `log_directory` in `postgresql.conf` |
