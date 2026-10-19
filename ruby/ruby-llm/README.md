# Ruby LLM (ruby_llm) with ruby-llm-otel + OpenTelemetry

A minimal Sinatra app that demonstrates **end-to-end OpenTelemetry instrumentation for [`ruby_llm`](https://github.com/crmne/ruby-llm) chat completions** using Last9's [`ruby-llm-otel`](https://github.com/last9/ruby-llm-otel) gem.

Every `POST /chat` produces one OTel trace containing the application's `demo.chat` span and the gem-emitted `chat <model>` child span. The child span carries the full GenAI semantic-convention attribute set — provider, model, temperature, token usage, finish reasons — plus Last9-extension cost attributes sourced from `ruby_llm`'s built-in pricing data.

## Prerequisites

- Ruby 3.2+ (3.4 recommended; this example pins `.ruby-version` to `3.4.8`)
- Bundler
- An OpenAI API key (the demo calls OpenAI directly via `ruby_llm`)
- One of:
  - An OTLP endpoint + credentials (Last9, Grafana Cloud, Honeycomb, a local OTel collector, etc.), OR
  - `USE_CONSOLE_EXPORTER=1` if you just want to see the spans on stdout

## Setup

```bash
cd ruby/ruby-llm
cp .env.example .env
# Edit .env with your OPENAI_API_KEY and OTLP details (or set USE_CONSOLE_EXPORTER=1)

bundle install
```

## Run

```bash
bundle exec ruby app.rb
```

The app boots on `http://0.0.0.0:4567`.

## Generate a trace

```bash
curl -X POST http://localhost:4567/chat \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "Name three rivers."}'
```

Response shape:

```json
{
  "model": "gpt-4o-mini",
  "trace_id": "5f3a7e...",
  "tokens": { "input": 14, "output": 18 },
  "cost_usd": 0.00012,
  "response": "Amazon, Nile, Mississippi."
}
```

Look up the returned `trace_id` in your OTel backend. You should see:

- One root span named **`demo.chat`** (kind: internal) — emitted by `app.rb`.
- One child span named **`chat gpt-4o-mini`** (kind: client) — emitted by `ruby-llm-otel`. This is the span you care about.

### Attributes on the `chat <model>` span

Request side:
- `gen_ai.system` = `openai`
- `gen_ai.operation.name` = `chat`
- `gen_ai.request.model`
- `gen_ai.request.temperature`

Response side:
- `gen_ai.response.id`, `gen_ai.response.model`, `gen_ai.response.finish_reasons`
- `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`

Cost (Last9 vendor extension, sourced from `ruby_llm`'s `Cost` class):
- `last9.cost.input_usd`, `last9.cost.output_usd`, `last9.cost.total_usd`
- `last9.cost.cache_read_usd`, `last9.cost.cache_write_usd`, `last9.cost.thinking_usd` (when applicable to the model)

Events (only when `CAPTURE_MESSAGE_CONTENT=1`):
- `gen_ai.user.message` per request turn
- `gen_ai.choice` with the response (JSON-encoded `{role, content}` matching OTel Python's shape)

## Local verification without OTLP credentials

Set `USE_CONSOLE_EXPORTER=1` in `.env`. The SDK swaps the OTLP exporter for the console exporter and prints each span as JSON-like text to stdout when the request completes — no Last9 / OTLP backend needed to confirm the gem is emitting correctly.

## Capturing prompt + completion content (PII warning)

By default, `capture_message_content` is **off** — no prompt or completion text reaches the OTel backend. Set `CAPTURE_MESSAGE_CONTENT=1` in `.env` to enable. When enabled, every `gen_ai.user.message` / `gen_ai.assistant.message` / `gen_ai.choice` event carries the message text. Exception messages on provider errors (which can echo prompt fragments back from the model API) are also forwarded verbatim into `span.status.description`.

The flag is read on every chat call — operators responding to a leak incident can flip it at runtime via `OpenTelemetry::Instrumentation::RubyLLM::Instrumentation.instance.config[:capture_message_content] = false` and the next call honors it without restarting the process.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Could not find ruby-llm-otel` during `bundle install` | The tag in the Gemfile (`v0.1.0.beta1`) no longer matches a tag in `last9/ruby-llm-otel`. Bump to the current tag from [the releases page](https://github.com/last9/ruby-llm-otel/releases). |
| `RuntimeError: OPENAI_API_KEY must be set` | Copy `.env.example` to `.env` and fill in the key. |
| Response returns but no spans land in your OTel backend | Verify `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS`. Set `USE_CONSOLE_EXPORTER=1` to see spans locally — confirms the gem is emitting; isolates the issue to the OTLP transport. |
| No `chat <model>` child span — only `demo.chat` | The gem isn't installed. Confirm `bundle install` resolved `ruby-llm-otel`, that `instrumentation.rb` is required before the chat call, and that `OpenTelemetry::Instrumentation::RubyLLM::Instrumentation.instance.installed?` returns true at boot. |
| 401 from OpenAI | Stale or invalid `OPENAI_API_KEY`. The gem doesn't intercept auth — failures propagate from the provider. The exception is recorded on the span before being re-raised. |

## Files

- `app.rb` — Sinatra HTTP shell with `/chat`, `/health`, `/` endpoints.
- `instrumentation.rb` — OTel SDK + ruby-llm-otel install. Required from `app.rb` before any chat call.
- `Gemfile` — pins `ruby-llm-otel` to a reviewed SHA from `last9/ruby-llm-otel`.
- `.env.example` — template for required + optional env vars.
