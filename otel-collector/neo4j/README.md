# Neo4j + OTel Collector

Collects Neo4j metrics via its Prometheus endpoint and ships to Last9.

> **Note:** Prometheus metrics require Neo4j Enterprise Edition. The `docker-compose.yaml` uses `neo4j:5-enterprise` with a 30-day evaluation license.

## Prerequisites

- Neo4j Enterprise 5.x installed and running
- OTel Collector installed as a binary
- Last9 OTLP credentials

## Neo4j Configuration

Enable the Prometheus metrics endpoint in `neo4j.conf`:

```
server.metrics.prometheus.enabled=true
server.metrics.prometheus.endpoint=0.0.0.0:2004
```

Restart Neo4j after making changes:

```bash
sudo systemctl restart neo4j
```

Verify the endpoint is working:

```bash
curl http://localhost:2004/metrics | head -20
```

## Quick Start (local Docker test)

```bash
cp .env.example .env
# Fill in OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION
docker compose up -d
```

## Production Setup (bare-metal)

1. Install OTel Collector:

   ```bash
   # AMD64
   wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_amd64.deb
   sudo dpkg -i otelcol-contrib_0.144.0_linux_amd64.deb
   # ARM64
   wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_arm64.deb
   sudo dpkg -i otelcol-contrib_0.144.0_linux_arm64.deb
   ```

2. Copy config:

   ```bash
   sudo cp otel-collector-config.yaml /etc/otelcol-contrib/config.yaml
   ```

3. Set credentials in `/etc/otelcol-contrib/otelcol-contrib.conf` and start:

   ```bash
   sudo systemctl enable --now otelcol-contrib
   ```

## Configuration

| Variable | Description |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION` | Last9 Basic auth header |
| `NEO4J_HOST` | Neo4j hostname (default: `localhost`) |

## Metrics Collected

- Transaction throughput (commits, rollbacks, active read/write)
- Query execution latency (slotted, pipelined, parallel)
- Bolt connection counts and idle sessions
- Page cache hit ratio and fault rates
- Store sizes (database, available)
- Cypher cache hit/miss rates
- JVM heap, GC pause times, thread counts
- System CPU, memory, disk, network via `hostmetrics`
