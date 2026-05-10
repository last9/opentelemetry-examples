# Cline — OpenTelemetry to Last9

Send Cline (VSCode/Cursor AI coding extension) telemetry — task turns, token usage, cost, tool calls, hooks, and AI output stats — to Last9 via OpenTelemetry.

Cline emits two OTel signal types:
- **Logs** — structured events for prompts, tool calls, errors, hooks
- **Metrics** — counters and histograms across task, cache, tools, errors, API latency, hooks, AI output, workspace

> Cline does **not** export traces yet (as of 3.82.0).

## Prerequisites

- A Last9 account ([app.last9.io](https://app.last9.io))
- OTLP credentials from **Integrations → OpenTelemetry** in the Last9 dashboard
- Cline extension installed in VSCode or Cursor (`saoudrizwan.claude-dev`)

## Option 1 — Direct Export to Last9 (no Collector)

Add the following to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export CLINE_OTEL_TELEMETRY_ENABLED=true
export CLINE_OTEL_METRICS_EXPORTER=otlp
export CLINE_OTEL_LOGS_EXPORTER=otlp
export CLINE_OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export CLINE_OTEL_EXPORTER_OTLP_ENDPOINT=https://<your-last9-otlp-endpoint>
export CLINE_OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-last9-auth-token>"
```

Reload, then **launch your editor from the same shell** so it inherits the env vars:

```bash
source ~/.zshrc
cursor .   # or `code .` for VSCode
```

Cline picks up the config on extension activation. Telemetry flushes:
- **Metrics** — every 60 seconds (`CLINE_OTEL_METRIC_EXPORT_INTERVAL`)
- **Logs** — every 5 seconds (`CLINE_OTEL_LOG_BATCH_TIMEOUT`)

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

3. Set Cline to send to the local collector:

   ```bash
   export CLINE_OTEL_TELEMETRY_ENABLED=true
   export CLINE_OTEL_METRICS_EXPORTER=otlp
   export CLINE_OTEL_LOGS_EXPORTER=otlp
   export CLINE_OTEL_EXPORTER_OTLP_PROTOCOL=grpc
   export CLINE_OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
   export CLINE_OTEL_EXPORTER_OTLP_INSECURE=true
   ```

4. Launch your editor from the same shell.

## Configuration Reference

### Core

| Variable | Purpose |
|---|---|
| `CLINE_OTEL_TELEMETRY_ENABLED` | Set to `true` to enable export (overrides user opt-out) |
| `CLINE_OTEL_METRICS_EXPORTER` | `otlp`, `console`, or comma-separated combo |
| `CLINE_OTEL_LOGS_EXPORTER` | Same as above |

### OTLP

| Variable | Purpose |
|---|---|
| `CLINE_OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc`, `http/json`, or `http/protobuf` |
| `CLINE_OTEL_EXPORTER_OTLP_ENDPOINT` | Collector URL (with port for gRPC) |
| `CLINE_OTEL_EXPORTER_OTLP_HEADERS` | `key=value` comma-separated auth headers |
| `CLINE_OTEL_EXPORTER_OTLP_INSECURE` | `true` to disable TLS for gRPC (local dev only) |

### Per-signal endpoint override (optional)

| Variable | Purpose |
|---|---|
| `CLINE_OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Metrics-only endpoint |
| `CLINE_OTEL_EXPORTER_OTLP_METRICS_PROTOCOL` | Metrics-only protocol |
| `CLINE_OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Logs-only endpoint |
| `CLINE_OTEL_EXPORTER_OTLP_LOGS_PROTOCOL` | Logs-only protocol |

### Tuning

| Variable | Default | Purpose |
|---|---|---|
| `CLINE_OTEL_METRIC_EXPORT_INTERVAL` | `60000` | Metric flush interval (ms) |
| `CLINE_OTEL_LOG_BATCH_SIZE` | `512` | Max log records per batch |
| `CLINE_OTEL_LOG_BATCH_TIMEOUT` | `5000` | Max wait before log flush (ms) |
| `CLINE_OTEL_LOG_MAX_QUEUE_SIZE` | `2048` | Max queued log records |

`.env` variables (Collector path):

| Variable | Purpose |
|---|---|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint (e.g. `https://otlp.last9.io`) |
| `LAST9_OTLP_AUTH` | Last9 Basic auth header value (`Basic <base64>`) |

## Verification

After running a Cline task for a minute:

1. **Metrics** — search for `cline_` in Last9 Metrics Explorer (e.g. `cline_turns_total`, `cline_tokens_input_total`, `cline_cost_total`)
2. **Logs** — filter by `service.name = cline` in Last9 Logs Explorer

<details>
<summary>Notable metrics</summary>

**Task / cost:**
- `cline.turns.total`, `cline.turns.per_task`
- `cline.tokens.input.total`, `cline.tokens.output.total`
- `cline.cost.total`, `cline.cost.per_event`

**Cache:**
- `cline.cache.write.tokens.total`, `cline.cache.read.tokens.total`, `cline.cache.hits.total`

**Tools / errors:**
- `cline.tool.calls.total`, `cline.tool.calls.per_task`
- `cline.errors.total`, `cline.errors.per_task`

**API latency:**
- `cline.api.ttft.seconds` — time-to-first-token
- `cline.api.duration.seconds` — full response duration
- `cline.api.throughput.tokens_per_second`

**AI output (developer outcome):**
- `cline.ai_output.accepted.{lines_added,lines_deleted,lines_changed,files_created,files_deleted,files_moved}`
- `cline.ai_output.rejected.*` — same set, for rejections

**Hooks:**
- `cline.hooks.executions.total`, `cline.hooks.duration.seconds`, `cline.hooks.failures.total`, `cline.hooks.cancellations.total`

**Workspace:**
- `cline.workspace.active_roots` (gauge)

</details>

## Debugging

Enable Cline OTel diagnostics:

```bash
export TEL_DEBUG_DIAGNOSTICS=true
```

Output appears in **Help → Toggle Developer Tools → Console** inside VSCode/Cursor.

## Troubleshooting

- **No data in Last9** — confirm `CLINE_OTEL_TELEMETRY_ENABLED=true` was set in the shell that launched the editor. GUI-launched editors don't inherit terminal env vars.
- **401 errors** — verify `CLINE_OTEL_EXPORTER_OTLP_HEADERS` is `Authorization=Basic <token>` (note the comma-separated `key=value` format, not HTTP header syntax with colons)
- **Metrics missing but logs flow** — Cline metrics use cumulative temporality by default. Last9 ingests cumulative natively. If you've manually overridden temporality to delta, ensure your collector path converts it.
