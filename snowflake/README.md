# Monitoring Snowflake with OpenTelemetry and Last9

A guide for setting up Snowflake monitoring using the OpenTelemetry Collector's `snowflake` receiver with Last9. It collects query, warehouse, storage, billing, and login metrics from Snowflake's `ACCOUNT_USAGE` views and sends them to Last9.

> **Note:** The `snowflake` receiver is alpha stability in collector-contrib. The config shape may change in future releases — pin your collector image version.

## Installation

### 1. Prerequisites

Ensure Docker and Docker Compose are installed on your system:

```bash
# Check Docker installation
docker --version

# Check Docker Compose installation
docker compose version
```

You also need:
- A Snowflake user with the `ACCOUNTADMIN` role (or a custom role granted access to `ACCOUNT_USAGE` views)
- A dedicated Snowflake warehouse for monitoring queries
- Username/password auth (the receiver does not yet support RSA key-pair auth — see [Troubleshooting](#troubleshooting))

### 2. Create a monitoring role and warehouse (optional but recommended)

```sql
CREATE WAREHOUSE IF NOT EXISTS monitoring_wh WITH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;
CREATE USER IF NOT EXISTS otel_monitor PASSWORD = '<strong-password>' DEFAULT_WAREHOUSE = monitoring_wh;
GRANT ROLE ACCOUNTADMIN TO USER otel_monitor;
```

`ACCOUNT_USAGE` views require `ACCOUNTADMIN` (or a role explicitly granted `IMPORTED PRIVILEGES` on the `SNOWFLAKE` database). Least-privilege setup is tracked upstream but not yet supported by the receiver.

### 3. Configure the OpenTelemetry Collector

The setup uses `otel-collector-config.yaml`, which defines:
- The `snowflake` receiver, connecting directly to your account via the Snowflake Go driver
- Opt-in metrics (billing, logins, row counts, query spill) enabled in addition to the receiver's defaults
- Last9 OTLP exporter configuration

Edit `otel-collector-config.yaml` and replace:
- `<SNOWFLAKE_USERNAME>`, `<SNOWFLAKE_PASSWORD>` — your monitoring user's credentials
- `<SNOWFLAKE_ACCOUNT>` — your account identifier, e.g. `xy12345.us-east-1`
- `<SNOWFLAKE_WAREHOUSE>` — the warehouse from step 2
- `<LAST9_OTLP_ENDPOINT>` and `<LAST9_OTLP_AUTH_HEADER>` — from Last9 Integrations

### 4. Start the Collector

```bash
docker compose -f docker-compose.yaml up -d
```

### Understanding the Setup

#### Snowflake Receiver

The receiver queries Snowflake's `ACCOUNT_USAGE` views on a fixed interval (`collection_interval: 30m` here) and converts the results into OTLP metrics. It connects directly — no separate exporter process is needed.

> **Data latency:** `ACCOUNT_USAGE` views lag live activity by up to 45 minutes. This is a Snowflake platform limitation, not specific to this receiver — Datadog and Grafana integrations see the same delay. Don't set `collection_interval` below ~10m; it won't surface data any sooner and just adds load to your monitoring warehouse.

#### Metrics reference

**Enabled by default:**

| Metric | Notes |
| --- | --- |
| `snowflake.query.executed` | Query count by status |
| `snowflake.query.blocked` | Blocked queries |
| `snowflake.query.queued_overload` | Queue overload |
| `snowflake.query.queued_provision` | Queue provisioning |
| `snowflake.query.execution_time.avg` | Avg execution time |
| `snowflake.query.compilation_time.avg` | Avg compilation time |
| `snowflake.query.bytes_written.avg` | Bytes written |
| `snowflake.query.bytes_deleted.avg` | Bytes deleted |
| `snowflake.queued_overload_time.avg` | Overload queue time |
| `snowflake.queued_provisioning_time.avg` | Provisioning queue time |
| `snowflake.queued_repair_time.avg` | Repair queue time |
| `snowflake.total_elapsed_time.avg` | Total elapsed time |
| `snowflake.database.bytes_scanned.avg` | Bytes scanned |
| `snowflake.database.query.count` | Query count per DB |
| `snowflake.storage.stage_bytes.total` | Stage storage bytes |
| `snowflake.storage.storage_bytes.total` | Total storage bytes |

**Opt-in (enabled in this example's config):**

| Metric | Notes |
| --- | --- |
| `snowflake.billing.cloud_service.total` | Credits used by cloud service |
| `snowflake.billing.total_credit.total` | Total credits used, account-wide |
| `snowflake.billing.virtual_warehouse.total` | Credits used by virtual warehouses |
| `snowflake.billing.warehouse.*` | Per-warehouse credit breakdowns |
| `snowflake.logins.total` | Login attempts (success/fail) |
| `snowflake.pipe.credits_used.total` | Snowpipe credit usage |
| `snowflake.rows_inserted.avg` / `rows_deleted.avg` / `rows_updated.avg` / `rows_produced.avg` / `rows_unloaded.avg` | Row-level throughput |
| `snowflake.query.bytes_spilled.local.avg` / `bytes_spilled.remote.avg` | Query spill to local/remote storage |
| `snowflake.query.data_scanned_cache.avg` | Cache hit rate |
| `snowflake.query.partitions_scanned.avg` | Partitions scanned per query |
| `snowflake.session_id.count` | Active session count |
| `snowflake.storage.failsafe_bytes.total` | Fail-safe storage bytes |

Remove or set `enabled: false` for any opt-in metric you don't need to reduce query load on your monitoring warehouse.

### Verification

Check the collector is running and scraping successfully:

```bash
docker ps
docker logs otel-collector
```

With `debug` exporter enabled, you should see Snowflake metrics logged locally within one `collection_interval`. Confirm the same metrics land in your Last9 tenant under Metrics.

### Troubleshooting

**No metrics after startup:** The first collection cycle only fires after `collection_interval` elapses (default 30m in this config). Check `docker logs otel-collector` for auth or query errors in the meantime.

**Auth errors:** Verify the user has `ACCOUNTADMIN` (or `ACCOUNT_USAGE` access) and that the warehouse is running and not suspended indefinitely.

**Need RSA / key-pair auth:** The `snowflake` receiver only supports username/password today. If your security policy requires key-pair auth, use the Prometheus path instead — Grafana Alloy's [`prometheus.exporter.snowflake`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.snowflake/) supports RSA, scraped via the collector's `prometheusreceiver`.

**Stale-looking data:** Expected — see the `ACCOUNT_USAGE` latency note above.

```bash
# Check container status
docker ps -a

# Restart the collector
docker compose restart otel-collector
```
