# FastAPI OTLP Exporter Compare (HTTP vs gRPC)

Reproduce and fix `requests.exceptions.ConnectionError: RemoteDisconnected` seen in production when OTLP HTTP exporter sits behind a load balancer that closes idle keep-alive TCP connections.

## Why

The OTLP HTTP exporter uses a long-lived `requests.Session`. Upstream LBs (ALB 60s, CloudFront 60s, nginx 75s) close idle TCP. Next export hits a half-closed socket:

```
requests.exceptions.ConnectionError: ('Connection aborted.',
  RemoteDisconnected('Remote end closed connection without response'))
```

gRPC exporter uses HTTP/2 with keepalive pings — no idle-socket problem. Newer Python OTel SDK (>=1.27) also retries on `ConnectionError` silently.

## What's here

- `app.py` — FastAPI + Uvicorn, OTel SDK, exporter selected by `OTEL_EXPORTER_OTLP_PROTOCOL`
- `repro.py` — driver that emits span, sleeps past LB idle window, emits again
- `flaky_server.py` — fake OTLP endpoint that half-closes every 2nd request. Deterministic repro
- `docker-compose.yaml` + `nginx.conf` — nginx with `keepalive_timeout 5s` in front of collector
- `requirements.txt` — current OTel (>=1.27) — error retried silently
- `requirements-legacy.txt` — customer's version (1.15) — raises full stack trace

## Reproduce (deterministic)

```bash
# 1. Install legacy SDK (1.15 — matches customer logs)
python3.11 -m venv .venv-legacy
.venv-legacy/bin/pip install -r requirements-legacy.txt

# 2. Start fake flaky OTLP server
.venv-legacy/bin/python flaky_server.py &

# 3. Run driver pointed at flaky server
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4319 \
.venv-legacy/bin/python repro.py
```

Expected: traceback with `RemoteDisconnected('Remote end closed connection without response')` — identical to customer log.

## Verify fixes

**Fix 1 — upgrade SDK (>=1.27):**
```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4319 \
.venv/bin/python repro.py
```
No traceback. Retry layer swallows it.

**Fix 2 — switch to gRPC (any SDK version):**
```bash
OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
.venv-legacy/bin/python repro.py
```
No traceback. HTTP/2 keepalive pings prevent idle closes.

## Alt: nginx + real collector

```bash
docker compose up -d
# Point exporter at http://localhost:4318 (HTTP) or http://localhost:4317 (gRPC)
```

Nginx `keepalive_timeout 5s` simulates an aggressive LB. Less deterministic than `flaky_server.py` because urllib3 can detect cleanly-closed sockets and reconnect.

## Production use

For the FastAPI app (`app.py`) against Last9:

```bash
cp .env.example .env
# edit .env with Last9 auth header
set -a && source .env && set +a
python app.py
curl localhost:8000/work
```

Recommended settings:
```
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io:443
OTEL_EXPORTER_OTLP_HEADERS=authorization=<your-last9-auth-header>
```

## Fix ranking

1. **gRPC exporter** — fixes root cause across all SDK versions
2. **Upgrade OTel libs to >=1.27.0** — silently retries on `ConnectionError`
3. **Keep HTTP, suppress noise** — if BSP retries succeed (no trace gaps in Last9):
   ```python
   logging.getLogger("opentelemetry.sdk._shared_internal").setLevel(logging.ERROR)
   ```
4. **Verify no data loss** — check Last9 for trace gaps during error bursts. BSP retries the failed batch; single log line usually means no loss.
