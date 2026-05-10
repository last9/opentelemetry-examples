# Codex CLI — OpenTelemetry to Last9

Send OpenAI Codex CLI telemetry (logs, traces, metrics) to Last9 — either directly or via a local OpenTelemetry Collector.

## Prerequisites

- A Last9 account ([app.last9.io](https://app.last9.io))
- OTLP credentials from **Integrations → OpenTelemetry** in the Last9 dashboard
- Codex CLI installed (`npm install -g @openai/codex` or `brew install codex`)

## Configuration Model

Codex reads OTel settings from `~/.codex/config.toml` under an `[otel]` table. Three exporters are configured separately — one each for **logs** (`exporter`), **traces** (`trace_exporter`), and **metrics** (`metrics_exporter`). All default to disabled (`metrics_exporter` defaults to Statsig). HTTP endpoints are **signal-specific** — Codex does not append `/v1/logs`, `/v1/traces`, `/v1/metrics` for you.

## Option 1 — Direct Export to Last9 (no Collector)

Add to `~/.codex/config.toml`:

```toml
analytics_enabled = true

[otel]
environment = "dev"
log_user_prompt = false

[otel.exporter.otlp-http]
endpoint = "https://otlp.last9.io/v1/logs"
protocol = "binary"
headers = { Authorization = "Basic <your_credentials>" }

[otel.trace_exporter.otlp-http]
endpoint = "https://otlp.last9.io/v1/traces"
protocol = "binary"
headers = { Authorization = "Basic <your_credentials>" }

[otel.metrics_exporter.otlp-http]
endpoint = "https://otlp.last9.io/v1/metrics"
protocol = "binary"
headers = { Authorization = "Basic <your_credentials>" }
```

Replace `<your_credentials>` with the Basic auth token from the Last9 OTel integration page. If your Last9 cluster uses a regional endpoint (e.g. `https://otlp-aps1.last9.io:443`), substitute it in all three endpoints.

Run Codex normally:

```bash
codex
```

## Option 2 — Local OpenTelemetry Collector

Useful when you want batching, retries, or to fan-out telemetry to multiple backends.

1. Copy `.env.example` to `.env` and fill in your Last9 credentials:

   ```bash
   cp .env.example .env
   ```

2. Start the collector:

   ```bash
   docker compose up -d
   ```

3. Point Codex at the local collector. Add to `~/.codex/config.toml`:

   ```toml
   analytics_enabled = true

   [otel]
   environment = "dev"

   [otel.exporter.otlp-grpc]
   endpoint = "http://localhost:4317"

   [otel.trace_exporter.otlp-grpc]
   endpoint = "http://localhost:4317"

   [otel.metrics_exporter.otlp-grpc]
   endpoint = "http://localhost:4317"
   ```

4. Run Codex:

   ```bash
   codex
   ```

## Configuration Keys

| Key | Purpose |
|-----|---------|
| `analytics_enabled` | Top-level flag. Must be `true` for `metrics_exporter` to fire. |
| `otel.environment` | Tags traces with environment (`dev`, `staging`, `prod`). Defaults to `dev`. |
| `otel.log_user_prompt` | If `true`, includes user prompts in exported logs. Default `false`. |
| `otel.exporter` | Logs exporter. Set to `otlp-http`, `otlp-grpc`, `none`, or `statsig`. |
| `otel.trace_exporter` | Spans exporter. Same shape as `exporter`. |
| `otel.metrics_exporter` | Metrics exporter. Defaults to `statsig` — set explicitly to send to Last9. |
| `otel.span_attributes` | Extra resource/span attributes (e.g. `team`, `user.id`). |

`.env` variables (Collector path):

| Variable | Purpose |
|----------|---------|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint (e.g. `https://otlp.last9.io`) |
| `LAST9_OTLP_AUTH` | Last9 Basic auth header value (`Basic <base64>`) |

## Verification

After running a Codex session for a minute:

1. **Traces** — Filter by `service.name = codex-cli` (or the originator name) in Last9 Traces Explorer
2. **Metrics** — Search for `codex.` in Last9 Metrics Explorer
3. **Logs/Events** — Filter by `service.name = codex-cli` in Last9 Logs Explorer

Codex flushes on session end. For long-running sessions, telemetry batches export periodically.

<details>
<summary>Notable signals</summary>

**Traces:** Codex emits spans for sessions, turns, model API calls, and tool executions. Span attributes include `model`, `conversation_id`, `account_id`, and tool-specific metadata.

**Metrics:** counters and histograms under the `codex.*` namespace — e.g. `codex.session_started`, `codex.request_latency`. Exact set evolves with Codex releases.

**Events (logs):** session start/stop, user prompts (when `log_user_prompt = true`), tool results, API errors.

</details>

## Troubleshooting

- **No data in Last9** — Confirm `analytics_enabled = true` at the top of `config.toml` (not nested under `[otel]`).
- **Metrics missing but traces flow** — `metrics_exporter` defaults to `statsig`; you must set it explicitly.
- **HTTP exporter errors** — Check your endpoint includes the signal-specific path (`/v1/logs`, etc.). Codex does not append it.
- **Startup warnings about invalid `otel.span_attributes` / `otel.tracestate`** — Codex logs these at startup and ignores the bad entries. Fix the keys to silence.
