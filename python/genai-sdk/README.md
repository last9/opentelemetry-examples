# GenAI SDK — Multi-Turn Conversation Tracing

Track LLM conversations, tool calls, and token usage using the Last9 GenAI SDK with OpenTelemetry.

## Prerequisites

- Python 3.10+
- A Last9 account ([app.last9.io](https://app.last9.io))
- OTLP credentials from **Integrations → OpenTelemetry** in the Last9 dashboard

## Quick Start

1. Create a virtual environment and install dependencies:

   ```bash
   python -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. Copy `.env.example` to `.env` and fill in your Last9 credentials:

   ```bash
   cp .env.example .env
   ```

3. Source the environment and run:

   ```bash
   source .env
   python app.py
   ```

## Configuration

| Variable | Purpose |
|----------|---------|
| `OTEL_SERVICE_NAME` | Service name in Last9 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint URL |
| `OTEL_EXPORTER_OTLP_HEADERS` | Authorization header (e.g., `Basic <token>`) |
| `DEPLOYMENT_ENV` | Environment tag (default: `local`) |

## Verification

After running the example, go to [**Traces Explorer**](https://app.last9.io/traces) in Last9:

1. Filter by `service.name = genai-example`
2. Filter by `gen_ai.conversation.id = demo-conversation-001` to see all 3 turns grouped
3. Expand a trace to see the span tree: `mithai.request` → `gen_ai.chat` → tool spans → `gen_ai.chat` (synthesis)
4. Click on `gen_ai.chat` spans to view `gen_ai.content.prompt` and `gen_ai.content.completion` events

## What This Example Demonstrates

- **`conversation_context`** — Groups 3 separate turns under one conversation ID
- **`workflow_context`** — Groups tool-use rounds as named workflows
- **Prompt/completion events** — Captures LLM inputs and outputs as span events
- **Token usage attributes** — Records `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens`
- **Tool execution spans** — Traces tool calls with input, approval status, and timing

<details>
<summary>Adapting for real LLM calls</summary>

Replace `simulate_llm_call()` with actual OpenAI or Anthropic API calls:

```python
from openai import OpenAI
from last9_genai import conversation_context

client = OpenAI()

with conversation_context(conversation_id="session_123", user_id="user_456"):
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": "Hello!"}],
    )
```

The `Last9SpanProcessor` automatically enriches all spans with conversation context — no additional instrumentation needed.

</details>
