# Braintrust + Last9 — Direct Dual Export, with Last9 GenAI SDK (Python)

Same dual-export shape as [`braintrust-direct`](../braintrust-direct/) (one `TracerProvider` with two `SpanProcessor` instances), enhanced with the [Last9 GenAI SDK](https://github.com/last9/python-ai-sdk).

What the SDK adds on top of the vanilla example:

- **`install()`** — wires the `TracerProvider`, `Last9SpanProcessor`, `LoggerProvider`, and `opentelemetry-instrumentation-openai-v2` in one call. The OpenAI client auto-emits `gen_ai.chat` spans, prompt/completion events, token usage, and cost in USD — no manual span code per call.
- **`conversation_context(conversation_id=...)`** — tags every span in the eval run with `gen_ai.conversation.id`, so Last9 can group LLM turns + score spans under one filter.
- **`agent_context(agent_name=..., agent_id=..., ...)`** — stamps `gen_ai.agent.{id,name,description,version}` on score spans so the Levenshtein scorer is distinguishable from any other scorer in a multi-scorer eval.
- **`workflow_context(workflow_id=..., workflow_type=...)`** — groups per-case work as a named workflow.

For a vanilla-OTel version without the SDK dependency, see [`braintrust-direct`](../braintrust-direct/).

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
| `OTEL_SERVICE_NAME` | Service name in Last9 |
| `OTEL_RESOURCE_ATTRIBUTES` | Comma-separated resource attrs (e.g., `deployment.environment=local`) |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP base URL (no `/v1/traces` suffix) |
| `LAST9_OTLP_AUTH` | Last9 auth header value (`Basic <base64-credentials>`) |
| `BRAINTRUST_API_KEY` | Braintrust API key |
| `BRAINTRUST_PARENT` | Braintrust routing target (e.g., `project_name:last9-otel-example`) |
| `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` | Set `true` to capture prompts/completions on `gen_ai.chat` spans |
| `OPENAI_API_KEY` | Used by the demo workload to call `gpt-4o-mini` |

## Verification

**Last9** — open [Traces Explorer](https://app.last9.io/traces):

1. Filter by `service.name = braintrust-direct-l9genai-example`
2. Open the latest trace; you will see the eval root span with two auto-emitted `gen_ai.chat` children (from auto-instrumentation) and two `Levenshtein` score spans
3. Every span carries `gen_ai.conversation.id = <eval_run_id>` (set by `conversation_context`)
4. Score spans carry `gen_ai.agent.id = scorer.levenshtein.v1` (set by `agent_context`)
5. `gen_ai.chat` spans carry `gen_ai.usage.cost_usd` (auto-set per model)

**Braintrust** — open the project named in `BRAINTRUST_PARENT`:

1. The latest run shows up under Logs
2. Score spans surface as `Levenshtein` scores attached to the eval

## What This Example Demonstrates

- All capabilities of [`braintrust-direct`](../braintrust-direct/) — dual-destination tracing with matching trace IDs, `gen_ai.*` semconv, Braintrust eval/score schema
- **Plus**: zero manual `gen_ai.chat` span code (auto-instrumentation handles it)
- **Plus**: conversation / agent / workflow grouping for filtering and breakdowns in Last9
- **Plus**: automatic cost-USD attribution on every LLM call
