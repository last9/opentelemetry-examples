# Monitoring MongoDB with OpenTelemetry

End-to-end example for monitoring self-hosted MongoDB using OpenTelemetry Collector. Collects metrics, logs, and extracts slow query details into structured attributes.

## Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop)
- [Docker Compose](https://docs.docker.com/compose/)

## Quick Start

1. **Start MongoDB and the OTel Collector:**

   ```sh
   docker compose up
   ```

   This starts:
   - MongoDB 5.0 with auth, profiling, and a pre-configured monitoring user
   - OTel Collector tailing MongoDB logs and scraping metrics

2. **Generate slow queries:**

   ```sh
   docker compose --profile generate up slow-query-generator
   ```

3. **Verify slow query extraction:**

   ```sh
   docker logs otel-collector 2>&1 | grep -B 10 "slow_query"
   ```

   You should see log records with attributes like:
   - `slow_query: Bool(true)`
   - `db.namespace: Str(...)` — database and collection
   - `db.operation.duration_ms: Double(...)` — query duration
   - `db.system: Str(mongodb)`
   - `SeverityText: WARN`

   User queries with `db.plan_summary: Str(COLLSCAN)` appear when queries exceed the 100ms `slowOpThresholdMs`. On fast hardware, the generated queries may complete under 100ms — the collector still processes any slow queries that MongoDB logs (including internal operations).

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint | — |
| `LAST9_AUTH_HEADER` | Last9 auth header | — |

To send data to Last9, uncomment the `otlp/last9` exporter in `otel-collector-config.yaml` and set the environment variables.

## What's Collected

**Metrics** (via `mongodb` receiver):
- Connection counts, memory usage (resident/virtual), operation latencies
- Page faults, active reads/writes, lock acquisition, health, uptime

**Logs** (via `filelog` receiver):
- MongoDB structured JSON logs parsed with timestamp and severity
- Slow queries (>100ms) enriched with `db.namespace`, `db.plan_summary`, `db.query_hash`, and more

## Stopping

```sh
docker compose down -v
```
