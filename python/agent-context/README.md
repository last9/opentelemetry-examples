# last9_genai agent identity example

Demonstrates `last9_genai.agent_context()` — a Python context manager that
attaches OTel GenAI semantic-convention agent attributes
(`gen_ai.agent.id`, `gen_ai.agent.name`, `gen_ai.agent.description`,
`gen_ai.agent.version`) to every span created inside it.

The script simulates a multi-agent handoff:

1. `Router` classifies the user's query.
2. `Refund Agent` handles the refund.

Both agents share the same `conversation_context` (so all their spans group
under one conversation in the Last9 LLM dashboard) and the Refund Agent adds
a `workflow_context` to track the nested retrieval / tool-use flow.

## Why this matters

OpenTelemetry's GenAI semantic conventions define a first-class way to identify
the agent that produced a span. Major frameworks (OpenAI Agents SDK,
`autogen-core`) already emit these on their own agent spans. `agent_context()`
lets you tag any hand-rolled or SDK-agnostic code the same way, so the Last9
Agents Monitoring dashboard can filter, group, and drill into spans by agent.

## Run

```bash
export OPENAI_API_KEY=...

export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-aps1.last9.io:443
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"
export OTEL_SERVICE_NAME=last9-genai-agent-demo
export OTEL_RESOURCE_ATTRIBUTES=deployment.environment=local

uv run --python 3.12 \
    --with 'last9-genai>=1.2' \
    --with opentelemetry-exporter-otlp \
    --with openai \
    python last9_agent_context.py
```

## What to verify in Last9

Open the Agents Monitoring dashboard and look for the conversation
`agent-demo-<timestamp>`. The spans should carry:

- `gen_ai.conversation.id` = the session id
- `user.id` = `demo-user`
- `gen_ai.agent.name` = `Router` on the classification call
- `gen_ai.agent.name` = `Refund Agent` on the reply call
- `gen_ai.agent.id`, `gen_ai.agent.description`, `gen_ai.agent.version`
  present on each call
- `workflow.id` = `refund-flow` on the Refund Agent span

## Requires

- `last9-genai >= 1.2.0` (ships `agent_context()`)
- `openai >= 1.0`
- `opentelemetry-exporter-otlp`
