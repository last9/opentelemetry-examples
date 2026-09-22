# Python WebSocket Manual Span

Adds a manual OpenTelemetry client span for a WebSocket HTTP upgrade. It records connection latency, peer, HTTP 101, and connection errors without recording message payloads or using the full socket lifetime as HTTP latency.

## Prerequisites

- Python 3.9+
- OTLP endpoint and credentials

## Quick Start

```bash
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
python test_app.py
cp .env.example .env
set -a; source .env; set +a
python app.py
```

`WEBSOCKET_URL` defaults to Postman's public echo endpoint. Replace it with your own WebSocket URL; query parameters are stripped from span attributes to avoid capturing credentials.

## Configuration

| Variable | Description |
| --- | --- |
| `OTEL_SERVICE_NAME` | Service name sent with the trace. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP HTTP endpoint. |
| `OTEL_EXPORTER_OTLP_HEADERS` | OTLP authorization header. |
| `WEBSOCKET_URL` | `ws://` or `wss://` endpoint to connect to. |
| `WEBSOCKET_MESSAGE` | Optional message sent to the example echo server. |

## Verification

Run the example, then find a client span named `GET <host>` in your tracing backend. It includes the peer host and port, sanitized URL, and `http.status_code=101` after a successful upgrade.

To use this in an existing application, keep `connect_websocket` and call it from an already-instrumented request or job. The span will then be a child of that operation.
