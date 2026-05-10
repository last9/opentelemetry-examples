# Braintrust + Last9 — Direct Dual Export (Python)

Send the same OpenTelemetry traces to **both** [Braintrust](https://www.braintrust.dev) (for LLM eval scores) and **Last9** (for full trace + APM observability) from a Python app, without an OpenTelemetry Collector.

Two `SpanProcessor` instances are attached to one `TracerProvider`:

- `BraintrustSpanProcessor` (from `braintrust[otel]`) — routes spans to Braintrust via the `x-bt-parent` header.
- `BatchSpanProcessor(OTLPSpanExporter(...))` — ships the same spans to Last9 over OTLP/HTTP.

Both backends see identical traces with matching trace/span IDs.

## Prerequisites

- Python 3.10+
- A [Last9 account](https://app.last9.io) with OTLP credentials (Integrations → OpenTelemetry)
- A [Braintrust account](https://www.braintrust.dev) with an API key
- An OpenAI API key

## Quick Start

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# fill in BRAINTRUST_API_KEY, LAST9_OTLP_ENDPOINT, LAST9_OTLP_AUTH, OPENAI_API_KEY

source .env
python app.py
```

## Configuration

| Variable | Purpose |
|----------|---------|
| `OTEL_SERVICE_NAME` | Service name shown in Last9 |
| `DEPLOYMENT_ENV` | Environment tag (default: `local`) |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP base URL (e.g., `https://otlp.last9.io`) |
| `LAST9_OTLP_AUTH` | Last9 auth header value (e.g., `Basic <base64-credentials>`) |
| `BRAINTRUST_API_KEY` | Braintrust API key |
| `BRAINTRUST_PARENT` | Braintrust routing target read by `BraintrustSpanProcessor` (e.g., `project_name:last9-otel-example`, `project_id:<uuid>`, or `experiment_id:<uuid>`). The collector example uses `BRAINTRUST_PROJECT` instead because the collector builds the `x-bt-parent` header from a project name only. |
| `OPENAI_API_KEY` | Used by the demo workload to call `gpt-4o-mini` |

## Verification

**Last9** — open [Traces Explorer](https://app.last9.io/traces):

1. Filter by `service.name = braintrust-direct-example`
2. Open the latest trace; you will see the eval root span with two `gen_ai.chat` children and two `Levenshtein` score spans
3. Span attributes include `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `braintrust.scores`

**Braintrust** — open the project listed in `BRAINTRUST_PARENT`:

1. The latest run shows up under Logs
2. The score spans surface as `Levenshtein` scores attached to the eval

## What This Example Demonstrates

- Dual-destination tracing from one OTel `TracerProvider` (no Collector required)
- `gen_ai.*` semantic-convention attributes on LLM spans (system, model, token usage, prompt/completion events)
- Braintrust eval/score spans emitted via OTLP using `braintrust.span_attributes.type = "score"` plus `braintrust.scores`
- Required `force_flush()` + `shutdown()` for short-lived CLI scripts (without these, `BatchSpanProcessor` drops buffered spans on exit)
