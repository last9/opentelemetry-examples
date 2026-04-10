# Redis Cloud + OTel Collector

Collects Redis metrics using the OpenTelemetry `redis` receiver and ships them to Last9. Works with Redis Cloud (Essentials and Pro), self-hosted Redis, and local dev.

## What it collects

OTel metric names use dots; they arrive in Last9 with dots replaced by underscores (e.g. `redis.memory.used` → `redis_memory_used`).

- **Memory**: `redis_memory_used`, `redis_memory_peak`, `redis_memory_rss`, `redis_memory_fragmentation_ratio`, `redis_maxmemory`
- **Cache efficiency**: `redis_keyspace_hits`, `redis_keyspace_misses`
- **Evictions**: `redis_keys_evicted`, `redis_keys_expired`
- **Connections**: `redis_clients_connected`, `redis_clients_blocked`, `redis_connections_rejected`
- **Throughput**: `redis_commands`, `redis_commands_processed`, `redis_net_input`, `redis_net_output`
- **Replication**: `redis_replication_offset`, `redis_slaves_connected`, `redis_role`
- **Persistence**: `redis_rdb_changes_since_last_save`, `redis_uptime`
- **Database**: `redis_db_keys`, `redis_db_expires`, `redis_db_avg_ttl`
- **Host**: CPU, memory, disk, network via `hostmetrics`

## Prerequisites

- Docker and Docker Compose
- Redis Cloud account (or local Redis for dev)
- Last9 account with OTLP credentials

## Quick start (local dev)

```bash
cp .env.example .env
# Fill in your Last9 credentials in .env

docker compose up -d

# Generate load to produce metrics
docker compose --profile generate up load-generator

# Check collector output
docker logs redis-otel-collector 2>&1 | grep -E "redis\.|Name:"

# Clean up
docker compose down
```

## Connecting to Redis Cloud

1. Get your endpoint from the Redis Cloud console (database → General → Endpoint)
2. Update `.env`:

```env
REDIS_ENDPOINT=redis-12345.c123.us-east-1-2.ec2.cloud.redislabs.com:12345
REDIS_PASSWORD=your-database-password
```

3. Update `otel-collector-config.yaml` to enable TLS (Redis Cloud requires it):

```yaml
receivers:
  redis:
    tls:
      insecure: false
      insecure_skip_verify: true  # or provide ca_file for full verification
```

4. Run the collector (no local Redis service needed):

```bash
docker compose up otel-collector
```

## Configuration

| File | Purpose |
|------|---------|
| `otel-collector-config.yaml` | Receiver, processors, exporter config |
| `.env` | OTLP credentials and Redis connection |
| `docker-compose.yaml` | Local Redis + OTel Collector services |
| `generate-load.sh` | Generates keys, hits, misses, and expiry events |

## Environment variables

| Variable | Description |
|----------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION` | `Basic <base64>` auth header |
| `REDIS_ENDPOINT` | Redis host:port (default: `redis:6379`) |
| `REDIS_PASSWORD` | Redis password (empty for passwordless) |

## Verification

```bash
# Confirm metrics are flowing in collector logs
docker logs redis-otel-collector 2>&1 | grep "redis.memory"

# Check Redis stats directly
redis-cli -h localhost -p 6379 INFO stats
redis-cli -h localhost -p 6379 INFO memory
```

In Last9 metrics explorer, search for `redis_` — metric names arrive with dots converted to underscores (e.g. `redis_memory_used`, `redis_keyspace_hits`).
