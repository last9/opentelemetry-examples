# NATS + OpenTelemetry + Last9

Java example demonstrating how to monitor a NATS messaging service with OpenTelemetry and send telemetry to Last9.

## What's covered

| Component | Instrumentation | Signal |
|-----------|----------------|--------|
| NATS Java client publish | Manual spans | Traces |
| NATS Java client subscribe | Manual spans + context propagation | Traces |
| NATS server metrics | prometheus-nats-exporter → OTel prometheus receiver | Metrics |
| JVM metrics | OTel Java agent | Metrics |

> The OTel Java agent does **not** auto-instrument the NATS client. Manual spans are added to produce `messaging.nats` traces with standard semantic conventions.

## Architecture

```
Java App (io.nats client)
  └── OTLP HTTP → localhost:4318 → OTel Collector

NATS Server (port 4222, HTTP monitoring: 8222)
  └── prometheus-nats-exporter (port 7777)
        └── prometheus scrape → OTel Collector

OTel Collector → Last9
```

## Prerequisites

- Docker and Docker Compose
- Java 17+
- Maven 3.8+
- Last9 account (OTLP endpoint + auth header)

## Quick Start

```bash
cp .env.example .env
# Fill in LAST9_OTLP_ENDPOINT and LAST9_OTLP_AUTH_HEADER

mvn clean package -q
docker compose up -d
java -javaagent:otel-javaagent.jar \
     -Dotel.service.name=nats-demo \
     -Dotel.exporter.otlp.endpoint=http://localhost:4318 \
     -Dotel.exporter.otlp.protocol=http/protobuf \
     -jar target/nats-otel-demo-1.0.0.jar
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NATS_URL` | `nats://localhost:4222` | NATS server URL |
| `LAST9_OTLP_ENDPOINT` | — | Last9 OTLP write URL |
| `LAST9_OTLP_AUTH_HEADER` | — | `Basic <base64>` auth header |
| `DEPLOYMENT_ENV` | `local` | Resource attribute for environment |

## Key Metrics from prometheus-nats-exporter

- `gnatsd_varz_in_msgs` / `gnatsd_varz_out_msgs` — messages in/out
- `gnatsd_varz_in_bytes` / `gnatsd_varz_out_bytes` — bytes in/out
- `gnatsd_connz_num_connections` — active connections
- `gnatsd_varz_mem` — server memory usage
- `gnatsd_varz_cpu` — server CPU usage
- `gnatsd_varz_slow_consumers` — slow consumer count
- `gnatsd_routez_num_routes` / `gnatsd_routez_in_msgs` — cluster route metrics
- JetStream: `gnatsd_varz_jetstream_*` (when JetStream is enabled)
