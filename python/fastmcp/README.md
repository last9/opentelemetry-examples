# Auto-instrumenting a FastMCP Server with OpenTelemetry

This example demonstrates how to instrument a [FastMCP](https://gofastmcp.com)
server with OpenTelemetry using auto-instrumentation. FastMCP has built-in
tracing for MCP operations (tool calls, resource reads, prompts), and
`opentelemetry-instrument` adds automatic spans for underlying libraries like
`httpx`, plus metrics and log correlation.

## Prerequisites

- Python 3.10+
- A [Last9](https://app.last9.io) account for the OTLP endpoint and credentials

## Quick Start

1. Create a virtual environment and install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Install auto-instrumentation packages:

```bash
opentelemetry-bootstrap -a install
```

3. Set up environment variables (get the Auth header from the
   [Last9 dashboard](https://app.last9.io)):

```bash
export OTEL_SERVICE_NAME=fastmcp-notes-server
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=<BASIC_AUTH_HEADER>"
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_TRACES_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_TRACES_SAMPLER=always_on
export OTEL_RESOURCE_ATTRIBUTES="service.name=fastmcp-notes-server,deployment.environment=local"
export OTEL_LOG_LEVEL=error
```

> **Note:** Replace `<BASIC_AUTH_HEADER>` with the URL-encoded value of your
> basic auth header. See
> [this post](https://last9.io/blog/whitespace-in-otlp-headers-and-opentelemetry-python-sdk/)
> for details on how the Python OTel SDK handles whitespace in headers.

4. Run the server with auto-instrumentation:

```bash
opentelemetry-instrument fastmcp run server.py
```

## What Gets Instrumented

### Traces

#### Automatic (FastMCP built-in)

FastMCP creates spans for every MCP operation with no code changes:

| Span Name               | When                        |
| ------------------------ | --------------------------- |
| `tools/call {name}`     | Every tool invocation       |
| `resources/read {uri}`  | Every resource read         |
| `prompts/get {name}`    | Every prompt render         |

Each span includes attributes like `rpc.system=mcp`, `rpc.method`, session ID,
and component type.

#### Automatic (opentelemetry-instrument)

The `opentelemetry-instrument` wrapper auto-patches libraries used inside your
tools:

- **httpx** — outbound HTTP requests get child spans with URL, method, status
- Any other library with an OTel instrumentor installed via
  `opentelemetry-bootstrap`

#### Error Recording on Spans

MCP tools return errors as strings, so spans look healthy by default even when
the operation failed. This example uses `span.record_exception()` and
`span.set_status(StatusCode.ERROR)` to make errors visible in the trace
waterfall:

```python
from opentelemetry.trace import StatusCode

with tracer.start_as_current_span("validate_note") as span:
    if not title.strip():
        span.set_status(StatusCode.ERROR, "empty title")
        return "Error: title cannot be empty"
```

For HTTP errors, `record_exception()` attaches the full stack trace:

```python
except httpx.HTTPStatusError as exc:
    span.record_exception(exc)
    span.set_status(StatusCode.ERROR, f"HTTP {exc.response.status_code}")
```

#### Custom Spans

Use `fastmcp.telemetry.get_tracer()` to add custom spans inside tool handlers:

```python
from fastmcp.telemetry import get_tracer

@mcp.tool()
async def my_tool(query: str) -> str:
    tracer = get_tracer()
    with tracer.start_as_current_span("my_custom_operation") as span:
        span.set_attribute("query.length", len(query))
        # your logic here
```

### Metrics

With `OTEL_METRICS_EXPORTER=otlp`, the auto-instrumentation collects runtime
and library metrics:

- **httpx** — request duration histograms, active connections
- **Python runtime** — GC counts, memory usage, CPU time
- **Process** — open file descriptors, thread count

These metrics land in Last9 alongside traces, giving you request rate, error
rate, and latency (RED metrics) out of the box.

### Logs (Trace-Log Correlation)

With `OTEL_LOGS_EXPORTER=otlp`, `opentelemetry-instrument` patches Python's
`logging` module so that every log record automatically includes `trace_id`,
`span_id`, and `trace_flags`. This means:

- Logs are exported to Last9 via OTLP alongside traces
- You can click a trace in Last9 Grafana and see its correlated log lines
- No manual trace context injection needed in your code

The example uses standard `logging`:

```python
import logging
logger = logging.getLogger("notes-server")

@mcp.tool()
async def add_note(title: str, content: str) -> str:
    logger.info("Note '%s' added", title)  # trace_id auto-injected
```

## Configuration

| Variable                          | Description                                  |
| --------------------------------- | -------------------------------------------- |
| `OTEL_SERVICE_NAME`              | Service name shown in traces                 |
| `OTEL_EXPORTER_OTLP_ENDPOINT`   | OTLP endpoint URL                            |
| `OTEL_EXPORTER_OTLP_HEADERS`    | Auth headers for the OTLP endpoint           |
| `OTEL_EXPORTER_OTLP_PROTOCOL`   | Protocol (`http/protobuf` or `grpc`)         |
| `OTEL_TRACES_EXPORTER`          | Traces exporter (`otlp`)                     |
| `OTEL_METRICS_EXPORTER`         | Metrics exporter (`otlp` or `none`)          |
| `OTEL_LOGS_EXPORTER`            | Logs exporter (`otlp` or `none`)             |
| `OTEL_TRACES_SAMPLER`           | Sampling strategy (`always_on`, `traceidratio`) |
| `OTEL_RESOURCE_ATTRIBUTES`      | Service metadata (name, env, version)        |

## MCP Tools and Resources

**Tools:**

- `add_note(title, content)` — Create a new note
- `update_note(title, content)` — Update an existing note
- `delete_note(title)` — Delete a note
- `search_notes(query)` — Search notes by keyword
- `fetch_url(url)` — Fetch a URL (demonstrates httpx auto-instrumentation)

**Resources:**

- `notes://list` — List all notes
- `notes://{title}` — Read a specific note

## Verification

Sign in to the [Last9 Dashboard](https://app.last9.io) and visit the APM
dashboard to see traces, metrics, and logs. You should see:

- `tools/call add_note` spans with child `validate_note` custom spans
- `tools/call fetch_url` spans with child `httpx` HTTP request spans
- Error spans (red) when validation fails or HTTP requests error out
- `resources/read notes://list` spans for resource access
- Correlated log lines attached to each trace
- Runtime and httpx metrics in the metrics explorer
