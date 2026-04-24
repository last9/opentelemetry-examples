# Cloudflare Tunnel Logs → Last9

Send `cloudflared` (Cloudflare Tunnel daemon) logs to Last9 via the OpenTelemetry Collector journald receiver, with correct severity mapping.

## How it works

`cloudflared` runs as a systemd service and writes logs to the system journal. The OTel Collector reads from journald, parses the severity from the log message body, and ships logs to Last9 over OTLP.

**Why parse severity from body, not `PRIORITY`?**  
`cloudflared` sets `PRIORITY=6` (INFO) for all log entries regardless of actual level. Severity must be extracted from the level token in the message body (`INF`, `WRN`, `ERR`, `DBG`, `FTL`).

## Prerequisites

- `cloudflared` installed and running as a systemd service
- Docker + Docker Compose on the same host
- Last9 account — get OTLP credentials from [Integrations](https://app.last9.io/integrations?integration=OpenTelemetry)

## Setup

**1. Clone and configure**

```bash
cp .env.example .env
```

Edit `.env`:

```bash
LAST9_OTLP_ENDPOINT=https://otlp-aps1.last9.io
LAST9_AUTH_HEADER=Basic <your_base64_encoded_credentials>
CLOUDFLARE_CONNECTOR_ID=<your_connector_id>        # from Cloudflare dashboard
CLOUDFLARE_TUNNEL_NAME=<your_tunnel_name>
SERVICE_NAMESPACE=production
```

**2. Verify cloudflared is running**

```bash
systemctl status cloudflared
journalctl -u cloudflared -n 20 --no-pager
```

**3. Start the collector**

```bash
docker compose up -d
```

**4. Verify logs are flowing**

```bash
# Check collector is reading journald
docker compose logs -f otelcol

# Look for lines like:
# "Sending" otelcol.signal=logs
```

## Configuration reference

| Field | Description |
|-------|-------------|
| `CLOUDFLARE_CONNECTOR_ID` | Connector ID from Cloudflare Zero Trust dashboard |
| `CLOUDFLARE_TUNNEL_NAME` | Human-readable tunnel name for filtering in Last9 |
| `SERVICE_NAMESPACE` | Logical grouping (e.g. `production`, `staging`) |

## Severity mapping

| cloudflared token | OTel severity |
|-------------------|---------------|
| `DBG` | Debug |
| `INF` | Info |
| `WRN` | Warn |
| `ERR` | Error |
| `FTL` | Fatal |

## Viewing logs

Visit [Last9 Log Explorer](https://app.last9.io/logs) and filter by `service.name = cloudflare-tunnel`.

## Troubleshooting

**No logs appearing**

```bash
# Confirm collector can read journald
docker compose exec otelcol journalctl -u cloudflared -n 5
# If permission denied, ensure the container's supplemental group matches
# the systemd-journal GID on your host: `getent group systemd-journal`
```

**All logs showing as INFO severity**

The regex parses the level token from the message. Confirm cloudflared log format:
```bash
journalctl -u cloudflared -n 5 --output=cat
# Expected format: 2026-01-01T00:00:00Z ERR some error message
```
