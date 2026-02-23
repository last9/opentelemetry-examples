# Monitoring MongoDB Atlas with OpenTelemetry

End-to-end example for monitoring MongoDB Atlas using the `mongodbatlasreceiver`. Collects metrics, logs, and extracts slow query details into structured attributes.

## Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop)
- MongoDB Atlas cluster (free tier M0 works)
- Atlas API key pair with `Project Data Access Read Only` role (for metrics + logs)

## Quick Start

1. **Copy and fill in credentials:**

   ```sh
   cp .env.example .env
   # Edit .env with your Atlas API keys, project/cluster names, and connection string
   ```

2. **Start the OTel Collector:**

   ```sh
   docker compose up
   ```

   The collector connects to the Atlas API and begins scraping metrics and polling logs.

3. **Generate slow queries** (requires Atlas connection string in `.env`):

   ```sh
   docker compose --profile generate up slow-query-generator
   ```

   This seeds 50K documents and runs COLLSCAN queries that exceed the 100ms threshold.

4. **Wait for Atlas logs** (3-5 minutes):

   Atlas delivers host logs asynchronously. After the delay, check the collector output:

   ```sh
   docker logs otel-collector-atlas 2>&1 | grep -B 10 "slow_query"
   ```

   You should see log records with attributes like:
   - `slow_query: Bool(true)`
   - `db.namespace: Str(testdb.users)`
   - `db.operation.duration_ms: Double(...)`
   - `db.plan_summary: Str(COLLSCAN)`
   - `SeverityText: WARN`

## Configuration

| Variable | Description | Required |
|----------|-------------|----------|
| `MONGODB_ATLAS_PUBLIC_KEY` | Atlas API public key | Yes |
| `MONGODB_ATLAS_PRIVATE_KEY` | Atlas API private key | Yes |
| `MONGODB_ATLAS_PROJECT_NAME` | Atlas project name | Yes |
| `MONGODB_ATLAS_CLUSTER_NAME` | Atlas cluster name | Yes |
| `MONGODB_ATLAS_URI` | Connection string for slow query generator | For generate profile |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint | No |
| `LAST9_AUTH_HEADER` | Last9 auth header | No |

To send data to Last9, uncomment the `otlp/last9` exporter in `otel-collector-config.yaml` and set the environment variables in `.env`.

## What's Collected

**Metrics** (via `mongodbatlas` receiver):
- Process memory (resident/virtual), cache size and ratios, connections
- Operation counts, query execution times, tickets available
- System CPU, memory, disk I/O, network throughput

**Logs** (via `mongodbatlas` receiver with `collect_host_logs: true`):
- MongoDB host logs with structured JSON parsing
- Slow queries (>100ms) enriched with `db.namespace`, `db.plan_summary`, `db.query_hash`, and more

## Atlas Tier Notes

- **M0 (free tier)**: Host log download and some monitoring APIs are not available. Metrics collection may be limited. Use M10+ for full metrics and log collection.
- **M10+**: Full support for metrics, host logs, audit logs, and slow query extraction.

## Stopping

```sh
docker compose down
```
