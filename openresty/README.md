# OpenResty OpenTelemetry Example

OpenTelemetry instrumentation for OpenResty (nginx + LuaJIT) sending traces, metrics, and logs to Last9.

## How it works

```
Traces:  otel_tracer.lua (log_by_lua) → OTLP/HTTP → otel-collector → Last9
Metrics: lua-resty-prometheus (/metrics) ──┐
         nginx stub_status (/nginx_status) ─┴→ otel-collector → Last9
Logs:    JSON access.log + error.log → filelog receiver → otel-collector → Last9
```

The tracer produces **two spans per request**:
- A `SERVER` span covering the full request lifecycle at the gateway
- A `CLIENT` child span for the upstream `proxy_pass` call with exact upstream latency

## Prerequisites

- Docker and Docker Compose
- Last9 account — get your OTLP endpoint and auth header from the [Last9 dashboard](https://app.last9.io)

## Quick Start

1. **Configure credentials**

   ```bash
   cp .env.example .env
   # Edit .env and fill in LAST9_OTLP_ENDPOINT and LAST9_OTLP_AUTH
   ```

2. **Update `otel-collector-config.yaml`** with your Last9 credentials:

   ```yaml
   exporters:
     otlp/last9:
       endpoint: <your-last9-otlp-endpoint>
       headers:
         Authorization: "Basic <your-last9-otlp-auth>"
   ```

3. **Start the stack**

   ```bash
   docker compose up --build
   ```

4. **Generate traffic**

   ```bash
   curl http://localhost/get
   curl http://localhost/status/200
   curl http://localhost/status/500   # triggers error span events
   ```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `OTEL_SERVICE_NAME` | `openresty` | Service name in traces and metrics |
| `OTEL_SERVICE_VERSION` | `1.0.0` | Service version attribute |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` | OTLP HTTP endpoint |
| `DEPLOYMENT_ENVIRONMENT` | `production` | `deployment.environment` resource attribute |

## Verification

Check the collector is receiving data:

```bash
# Collector logs (traces, metrics, logs printed by debug exporter)
docker compose logs otel-collector -f

# Verify metrics endpoint
curl http://localhost:9145/metrics

# Verify nginx stub_status
curl http://localhost:9145/nginx_status
```

## Customising the upstream

Replace the `httpbin` service in `docker-compose.yaml` and the `upstream upstream-app` block in `conf.d/default.conf` with your own application.

## Project Structure

```
.
├── Dockerfile                  # OpenResty + lua-resty-prometheus via opm
├── docker-compose.yaml
├── nginx.conf                  # Main nginx config (JSON logging, lua_shared_dict)
├── conf.d/
│   ├── default.conf            # App server with Lua tracing hooks
│   └── status.conf             # /metrics and /nginx_status endpoints
├── lua/
│   ├── otel_tracer.lua         # W3C trace context propagation + OTLP export
│   └── metrics_init.lua        # lua-resty-prometheus counters and histograms
└── otel-collector-config.yaml  # All three signal pipelines
```
