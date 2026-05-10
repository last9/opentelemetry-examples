# Braintrust + Last9 — Collector Dual Export (Node.js)

Send the same OpenTelemetry traces to **both** [Braintrust](https://www.braintrust.dev) (for LLM eval scores) and **Last9** (for full trace + APM observability) using an OpenTelemetry Collector for fan-out.

The app emits OTLP/HTTP to a local Collector. The Collector's trace pipeline declares two `otlphttp` exporters — one for Braintrust, one for Last9 — and routes every span to both.

Compared to the [direct mode](../braintrust-direct/), this pattern keeps the app vendor-agnostic: routing, headers, and per-backend filtering live entirely in `otel-collector-config.yaml`. Useful when you want to add or remove backends without redeploying app code.

## Prerequisites

- Docker + Docker Compose
- A [Last9 account](https://app.last9.io) with OTLP credentials (Integrations → OpenTelemetry)
- A [Braintrust account](https://www.braintrust.dev) with an API key
- An OpenAI API key

## Quick Start

```bash
cp .env.example .env
# fill in BRAINTRUST_API_KEY, BRAINTRUST_PROJECT, LAST9_OTLP_ENDPOINT, LAST9_OTLP_AUTH, OPENAI_API_KEY

docker compose up --build
```

The app runs once, emits the eval traces, and exits. The Collector keeps running; press `Ctrl+C` to stop it.

### Run the app on the host instead of inside Docker

```bash
docker compose up otel-collector  # collector only

npm install
source .env
npm start
```

`OTEL_EXPORTER_OTLP_ENDPOINT` in `.env.example` already points at `http://localhost:4318` for this case.

## Configuration

| Variable | Used by | Purpose |
|----------|---------|---------|
| `OTEL_SERVICE_NAME` | App | Service name shown in Last9 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | App | Local collector address (`http://otel-collector:4318` inside compose, `http://localhost:4318` on host) |
| `DEPLOYMENT_ENV` | App | Environment tag |
| `OPENAI_API_KEY` | App | Used by the demo workload to call `gpt-4o-mini` |
| `LAST9_OTLP_ENDPOINT` | Collector | Last9 OTLP base URL |
| `LAST9_OTLP_AUTH` | Collector | Last9 auth header value (`Basic <base64-credentials>`) |
| `BRAINTRUST_API_KEY` | Collector | Braintrust API key |
| `BRAINTRUST_PROJECT` | Collector | Braintrust project name. Built into the `x-bt-parent: project_name:${BRAINTRUST_PROJECT}` header by the collector exporter. The direct-mode example uses `BRAINTRUST_PARENT` (full prefix:value) because the SDK extension expects it that way. |

## Verification

**Last9** — open [Traces Explorer](https://app.last9.io/traces):

1. Filter by `service.name = braintrust-collector-example`
2. Open the latest trace; you will see the eval root span with two `gen_ai.chat` children and two `Levenshtein` score spans

**Braintrust** — open the project named in `BRAINTRUST_PROJECT`:

1. The latest run shows up under Logs
2. The score spans surface as `Levenshtein` scores attached to the eval

## What This Example Demonstrates

- Single-endpoint app instrumentation that fans out to multiple backends at the Collector
- Two named `otlphttp` exporters in one trace pipeline
- `gen_ai.*` semantic-convention attributes on LLM spans
- Braintrust eval/score spans emitted via OTLP using `braintrust.span_attributes.type = "score"` plus `braintrust.scores`
- Required `provider.forceFlush()` + `provider.shutdown()` for short-lived CLI scripts
