# goose — OpenTelemetry to Last9

Send goose (Block's open-source AI coding agent) telemetry — traces, metrics, and logs — to Last9 via OpenTelemetry.

goose uses **standard `OTEL_*` env vars** (no custom prefix) and emits all three signal types out of the box. Default temporality is **cumulative**, so it ingests cleanly into Last9 without conversion.

## Prerequisites

- A Last9 account ([app.last9.io](https://app.last9.io))
- OTLP credentials from **Integrations → OpenTelemetry** in the Last9 dashboard
- goose installed — `brew install block-goose-cli` or follow [install docs](https://block.github.io/goose/docs/getting-started/installation)

## Option 1 — Direct Export to Last9 (no Collector)

Add the following to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="https://<your-last9-otlp-endpoint>"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-last9-auth-token>"
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_SERVICE_NAME=goose
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=local"
```

Reload, then run goose:

```bash
source ~/.zshrc
goose session
```

Telemetry flushes:
- **Traces** — on span end
- **Metrics** — every 60 seconds (default OTel SDK)
- **Logs** — on log emission (or batched briefly)

## Option 2 — Local OpenTelemetry Collector

Useful for batching, retries, or fan-out to multiple backends.

1. Copy `.env.example` to `.env` and fill in your Last9 credentials:

   ```bash
   cp .env.example .env
   ```

2. Start the collector:

   ```bash
   docker compose up -d
   ```

3. Point goose at the local collector:

   ```bash
   export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
   export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
   export OTEL_SERVICE_NAME=goose
   ```

4. Run goose normally.

## Configuration Reference

goose honors the standard [OpenTelemetry SDK environment variables](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/).

### Core

| Variable | Purpose |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Base OTLP endpoint (SDK appends `/v1/traces`, etc.) |
| `OTEL_EXPORTER_OTLP_HEADERS` | `key=value` comma-separated auth headers |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc`, `http/protobuf`, or `http/json` |
| `OTEL_SERVICE_NAME` | Service name override (default: `goose`) |
| `OTEL_RESOURCE_ATTRIBUTES` | Comma-separated `key=value` resource tags |
| `OTEL_SDK_DISABLED` | Set `true` to disable all OTel export |

### Per-signal control

| Variable | Purpose |
|---|---|
| `OTEL_TRACES_EXPORTER` | `otlp`, `console`, `none` |
| `OTEL_METRICS_EXPORTER` | `otlp`, `console`, `none` |
| `OTEL_LOGS_EXPORTER` | `otlp`, `console`, `none` |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Traces-only endpoint override |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Metrics-only endpoint override |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Logs-only endpoint override |

### Sampling

| Variable | Purpose |
|---|---|
| `OTEL_TRACES_SAMPLER` | `parentbased_traceidratio`, `always_on`, etc. |
| `OTEL_TRACES_SAMPLER_ARG` | Sampling ratio (e.g. `0.1` for 10%) |

### Anonymous usage data (separate from OTel)

| Variable | Purpose |
|---|---|
| `GOOSE_TELEMETRY_ENABLED` | Enable/disable anonymous usage data collection (separate from OTel above) |

`.env` variables (Collector path):

| Variable | Purpose |
|---|---|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint (e.g. `https://otlp.last9.io`) |
| `LAST9_OTLP_AUTH` | Last9 Basic auth header value (`Basic <base64>`) |

## Verification

After running a goose session for a minute:

1. **Traces** — filter by `service.name = goose` in Last9 Traces Explorer. Notable spans: `reply_stream`, `dispatch_tool_call`
2. **Metrics** — search for series with `service_name="goose"` in Metrics Explorer
3. **Logs** — filter by `service.name = goose` in Logs Explorer

## Goose Configuration File

Alternative: configure via `~/.config/goose/config.yaml`:

```yaml
otel_exporter_otlp_endpoint: "https://<your-last9-otlp-endpoint>"
otel_exporter_otlp_timeout: 30
```

Env vars take precedence over config file values.

## Troubleshooting

- **No data in Last9** — confirm `echo $OTEL_EXPORTER_OTLP_ENDPOINT` in the same shell where you run `goose`. Restart goose after any env var change.
- **401 errors** — verify `OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <token>` (key=value format, no HTTP colon syntax).
- **High trace volume** — set `OTEL_TRACES_SAMPLER=parentbased_traceidratio` and `OTEL_TRACES_SAMPLER_ARG=0.1` to sample 10%.
- **Service name appears as `unknown_service`** — set `OTEL_SERVICE_NAME=goose` explicitly. goose's resource builder defaults to `goose` but env var takes precedence.
