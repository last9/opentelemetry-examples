# AutoGen + last9_genai demo

Demonstrates capturing LLM messages, tool calls, and completions onto spans when
using AutoGen's `AssistantAgent` with OpenAI models, so Last9's LLM dashboard
can render the conversation.

## Why this is needed

- AutoGen emits its own OTel spans via `autogen-core` tracer (`invoke_agent`,
  `execute_tool`, `chat {model}`), but does NOT put message content or token
  usage on them.
- `opentelemetry-instrumentation-openai-v2` does populate the `chat` span's
  request/response metadata, but emits message content as **OTel log events**
  (per the new GenAI semantic conventions), not as span attributes.
- The Last9 LLM dashboard reads span attributes (`gen_ai.prompt`, `gen_ai.completion`)
  or span events (`gen_ai.content.prompt`, `gen_ai.content.completion`), so the
  log-based messages never reach the dashboard.

`last9_genai.Last9LogToSpanProcessor` bridges this gap: it listens to the GenAI
log events and promotes their payloads onto the active span as both flat
JSON-array attributes (what the dashboard parses) and indexed attributes
(AgentOps/Traceloop compatible).

## Run

```bash
export OPENAI_API_KEY=...

uv run --python 3.12 \
    --with autogen-agentchat \
    --with 'autogen-ext[openai]' \
    --with opentelemetry-instrumentation-openai-v2 \
    --with 'last9-genai @ file:///Users/prathamesh2_/Projects/python-ai-sdk' \
    --with openai \
    --with 'wrapt<2' \
    python autogen_last9_genai.py
```

### Python version

Use Python 3.12 or 3.13. Python 3.14 currently breaks with
`opentelemetry-instrumentation-openai-v2 2.3b0` because of a `wrapt` kwarg
signature change — instrumentation fails to wrap and no log events are emitted.

## What to verify

After the run, the `chat gpt-4o-mini` span should include:

- `gen_ai.prompt`: JSON array of `{role, content}` messages
- `gen_ai.completion`: JSON array of choice objects with `tool_calls`
- span events `gen_ai.content.prompt` / `gen_ai.content.completion`
- `gen_ai.conversation.id`, `workflow.id`, `user.id` from `conversation_context`
  / `workflow_context`

Tool-call argument and result capture for the AutoGen `execute_tool` span is
not yet implemented — tracked as Phase 2 work in `last9_genai`.
