# Cerebrium + OpenTelemetry Auto-Instrumentation → Last9

Deploy a FastAPI app on Cerebrium with zero OpenTelemetry code in your source files. `opentelemetry-instrument` runs in the entrypoint and auto-patches FastAPI, `requests`, `httpx`, and logging at process startup. Traces ship to Last9 over OTLP/HTTP.

This complements Cerebrium's platform-side **metrics export** (resource and execution metrics shipped from the platform itself). Together you get metrics + traces in Last9.

## Prerequisites

- Cerebrium account with the CLI installed: `pip install cerebrium`
- Last9 account — grab the OTLP HTTP endpoint and Auth Header from **Integrations → OpenTelemetry** in [app.last9.io](https://app.last9.io)

## Quick Start

1. **Clone this directory and set up secrets in Cerebrium.**

   ```bash
   cerebrium login
   cerebrium secrets set OTEL_EXPORTER_OTLP_ENDPOINT https://otlp-aps1.last9.io
   cerebrium secrets set OTEL_EXPORTER_OTLP_HEADERS 'Authorization=Basic <your-token>'
   cerebrium secrets set OTEL_EXPORTER_OTLP_PROTOCOL http/protobuf
   cerebrium secrets set OTEL_SERVICE_NAME otel-autoinstrument-last9
   ```

   See `.env.example` for the full list of variables.

2. **Deploy.**

   ```bash
   cerebrium deploy
   ```

   Build runs `opentelemetry-bootstrap --action=install` which detects every supported library in your pip deps and pulls the matching instrumentation package. Look for it in the build logs.

3. **Invoke the app.**

   ```bash
   curl -X POST https://api.cortex.cerebrium.ai/v4/p-XXXXXX/otel-autoinstrument-last9/predict \
     -H "Authorization: Bearer <cerebrium-token>" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "trace me", "run_id": "test-1"}'
   ```

4. **View traces in Last9.**

   Open [Traces Explorer](https://app.last9.io/traces), filter by `service.name = otel-autoinstrument-last9`. You should see a `POST /predict` parent span with child `GET` spans for the two `httpbin.org` calls.

## How it works

- `cerebrium.toml` defines `entrypoint = ["opentelemetry-instrument", "uvicorn", "main:app", ...]`. Cerebrium runs that command directly, so the OTel launcher gets first-class control of process startup.
- `opentelemetry-instrument` reads `OTEL_*` env vars, sets `PYTHONPATH` to OTel's `sitecustomize.py`, then `exec`s your command. From that point every Python import gets the OTel-patched version of the library.
- `main.py` is just FastAPI. Nothing else.

## What gets auto-instrumented

Anything in the dependencies that has an `opentelemetry-instrumentation-*` package on PyPI. Common picks for AI workloads:

| Library | Captures |
|---|---|
| `fastapi` | Request span per route, status code, route template |
| `requests`, `httpx`, `urllib3` | Outbound HTTP spans with method, URL, status |
| `logging` | Trace and span IDs injected into log records |
| `openai`, `anthropic` | Per-call LLM spans with model, token counts |
| `sqlalchemy`, `psycopg2`, `redis` | DB and cache spans |

To add more, list them in `[cerebrium.dependencies.pip]` and re-deploy — `opentelemetry-bootstrap` picks them up.

## Combining with Cerebrium's metrics export

This example handles **traces only**. For platform-side **metrics** (CPU, GPU, container counts, run latencies), configure Cerebrium's dashboard:

- **Integrations → Metrics Export → Custom OTLP**
- Endpoint: `https://otlp-aps1.last9.io` (base URL — Cerebrium auto-appends `/v1/metrics`)
- Auth Header Name: `Authorization`
- Auth Header Value: `Basic <token>`

Full guide: [Cerebrium integration on docs.last9.io](https://last9.io/docs/integrations/cerebrium)

## Troubleshooting

- **No traces in Last9.** Check Cerebrium build logs for the `opentelemetry-bootstrap` output — it must list at least `fastapi` and `requests`. If absent, the deps didn't install or the shell command failed.
- **`AttributeError: ... has no attribute 'instrument'` at startup.** A library was imported before `opentelemetry-instrument` could patch it — make sure no `pre_build_commands` or custom shell commands import your app modules.
- **Header malformed errors from OTLP.** `OTEL_EXPORTER_OTLP_HEADERS` uses `=` between header name and value, not `:`. Correct format: `Authorization=Basic <token>`.
- **Spans appear but with no parent/child link.** A library is being imported at module top level before the sitecustomize fires. Move the import inside the function, or add an explicit `*Instrumentor().instrument()` call in a small bootstrap module loaded first.
