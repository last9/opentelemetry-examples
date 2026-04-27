# Python OTel Trace Filtering

Demonstrates two approaches to exclude noisy, non-actionable spans (e.g. health-check endpoints) from OpenTelemetry traces sent to Last9.

## The Problem

Health-check endpoints polled every 30s generate ~2,880+ spans/day — identical, low-value traces that flood your dashboard and make debugging harder.

## Approach 1: `OTEL_PYTHON_EXCLUDED_URLS` (recommended)

Zero code change. Set the env var before running `opentelemetry-instrument`:

```bash
export OTEL_PYTHON_EXCLUDED_URLS="health-check,ping,ready,live,metrics"
```

Patterns are comma-separated regexes matched via `re.search()` on the full URL. Partial matches apply — `health-check` excludes `/health-check`, `/api/health-check`, etc.

Framework-specific variants take precedence if you need different exclusions per service:

```bash
export OTEL_PYTHON_FASTAPI_EXCLUDED_URLS="health-check,ping"
export OTEL_PYTHON_FLASK_EXCLUDED_URLS="health,ready"
```

## Approach 2: Custom Sampler

For cases that need more control (filter by status code, tenant, business logic). See `sampler.py` and `app_with_sampler.py`.

The `ParentBased` wrapper in `sampler.py` is critical — it propagates the `DROP` decision to all child spans of a filtered root span.

## Prerequisites

- Python 3.8+
- Last9 account with OTLP credentials

## Quick Start

```bash
# Install dependencies
uv venv && uv pip install -r requirements.txt

# Copy and fill in credentials
cp .env.example .env

# Approach 1: env-var exclusion (zero code)
source .env
opentelemetry-instrument uvicorn app:app --host 0.0.0.0 --port 8000

# Approach 2: custom sampler
source .env
python app_with_sampler.py
```

## Configuration

| Variable | Description |
|----------|-------------|
| `OTEL_PYTHON_EXCLUDED_URLS` | Comma-separated regex patterns for URLs to exclude |
| `OTEL_PYTHON_FASTAPI_EXCLUDED_URLS` | FastAPI-specific exclusions (overrides generic) |
| `OTEL_SERVICE_NAME` | Service name in Last9 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | `Authorization=<token>` |

## Verification

```bash
# Generate health-check traffic (should NOT appear in Last9)
for i in {1..10}; do curl -s http://localhost:8000/health-check; done

# Generate real traffic (SHOULD appear in Last9)
curl http://localhost:8000/api/orders
curl http://localhost:8000/api/orders/ord-1
```

Check [Last9 Traces](https://app.last9.io) — only `/api/*` spans should appear.
