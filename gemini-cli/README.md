# Gemini CLI — OpenTelemetry to Last9

Send Google's [Gemini CLI](https://github.com/google-gemini/gemini-cli) telemetry — traces, metrics, and logs — to Last9 via OpenTelemetry.

Gemini CLI emits all three OpenTelemetry signal types. Keep all three on — combined volume is low and traces add per-call model latency / token attribution that metrics alone cannot.

- **Traces** — spans for tool calls, API requests, agent runs (set `GEMINI_TELEMETRY_TRACES_ENABLED=true`)
- **Metrics** — session counts, token usage, latency, file ops, agent durations
- **Logs** — structured events for prompts, API requests/responses, slash commands, file operations

## Prerequisites

- A Last9 account ([app.last9.io](https://app.last9.io))
- OTLP credentials from **Integrations → OpenTelemetry** in the Last9 dashboard
- Gemini CLI installed (`npm install -g @google/gemini-cli`)

## Option 1 — Direct Export to Last9 (no Collector)

Gemini CLI's OTLP exporters take `url` only, but the underlying OpenTelemetry JS SDK reads standard `OTEL_EXPORTER_OTLP_HEADERS` from env for authentication — so direct export works.

```bash
# Gemini CLI telemetry switches
export GEMINI_TELEMETRY_ENABLED=true
export GEMINI_TELEMETRY_TARGET=local
export GEMINI_TELEMETRY_OTLP_ENDPOINT="https://<your-last9-otlp-endpoint>"
export GEMINI_TELEMETRY_OTLP_PROTOCOL=http
export GEMINI_TELEMETRY_TRACES_ENABLED=true

# Standard OTel env — picked up by SDK for auth headers
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-last9-auth-token>"
```

Reload and run:

```bash
source ~/.zshrc
gemini -p "explain this repo"
```

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

3. Point Gemini CLI at the local collector:

   ```bash
   export GEMINI_TELEMETRY_ENABLED=true
   export GEMINI_TELEMETRY_TARGET=local
   export GEMINI_TELEMETRY_OTLP_ENDPOINT=http://localhost:4317
   export GEMINI_TELEMETRY_OTLP_PROTOCOL=grpc
   export GEMINI_TELEMETRY_TRACES_ENABLED=true
   unset OTEL_EXPORTER_OTLP_HEADERS   # collector handles auth
   ```

4. Run Gemini CLI:

   ```bash
   gemini
   ```

## Configuration Reference

### Gemini CLI-specific

| Variable | Default | Purpose |
|---|---|---|
| `GEMINI_TELEMETRY_ENABLED` | `false` | Master toggle |
| `GEMINI_TELEMETRY_TARGET` | `local` | `local` (OTLP) or `gcp` (Google Cloud) |
| `GEMINI_TELEMETRY_OTLP_ENDPOINT` | `http://localhost:4317` | OTLP endpoint (base URL — `/v1/traces` etc. appended) |
| `GEMINI_TELEMETRY_OTLP_PROTOCOL` | `grpc` | `grpc` or `http` |
| `GEMINI_TELEMETRY_TRACES_ENABLED` | `false` | Set `true` to export spans (recommended) |
| `GEMINI_TELEMETRY_LOG_PROMPTS` | `true` | Include prompt text in logs |
| `GEMINI_TELEMETRY_OUTFILE` | — | Write to local file instead of OTLP |

### Standard OTel env (used for auth headers)

| Variable | Purpose |
|---|---|
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=Basic <token>` |
| `OTEL_EXPORTER_OTLP_{TRACES,METRICS,LOGS}_HEADERS` | Per-signal override |

### `.env` variables (Collector path)

| Variable | Purpose |
|---|---|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint (e.g. `https://otlp.last9.io`) |
| `LAST9_OTLP_AUTH` | Last9 Basic auth header (`Basic <base64>`) |

## Verification

After running a Gemini CLI session for a minute:

1. **Traces** — filter by `service.name = gemini-cli` in Last9 Traces Explorer. Span name: `llm_call`.
2. **Metrics** — search for `gemini_cli_session_count_total`, `gemini_cli_api_request_count_total`, `gemini_cli_token_usage_total`
3. **Logs** — filter by `service.name = gemini-cli` in Last9 Logs Explorer

<details>
<summary>Notable metrics</summary>

| Metric | Type |
|---|---|
| `gemini_cli.session.count` | counter |
| `gemini_cli.tool.call.count` | counter |
| `gemini_cli.tool.call.latency` | histogram |
| `gemini_cli.api.request.count` | counter |
| `gemini_cli.api.request.latency` | histogram |
| `gemini_cli.token.usage` | counter |
| `gemini_cli.file.operation.count` | counter |
| `gemini_cli.lines.changed` | counter |
| `gemini_cli.agent.run.count` | counter |
| `gemini_cli.agent.duration` | histogram |
| `gemini_cli.startup.duration` | histogram |
| `gemini_cli.memory.usage` | gauge |
| `gemini_cli.cpu.usage` | gauge |
| `gen_ai.client.token.usage` | counter (GenAI semconv) |
| `gen_ai.client.operation.duration` | histogram (GenAI semconv) |

</details>

## Troubleshooting

- **No data in Last9** — confirm `echo $GEMINI_TELEMETRY_ENABLED` returns `true` in the shell that ran `gemini`. Restart shell after editing `~/.zshrc`.
- **Authentication errors** — verify `OTEL_EXPORTER_OTLP_HEADERS` is `Authorization=Basic <token>` (key=value format, not HTTP colon syntax). Trailing whitespace breaks it.
- **Traces missing** — make sure `GEMINI_TELEMETRY_TRACES_ENABLED=true` is set. Gemini CLI defaults to `false`, so spans only flow when you explicitly enable them.
- **gRPC connection refused** — make sure `-p 4317:4317` is exposed (collector path) and you're using `grpc` protocol with `http://localhost:4317` (not `https`).
