# Monitoring Oracle XE with OpenTelemetry

A guide for setting up Oracle XE monitoring using OpenTelemetry Collector. This setup collects Oracle database metrics and sends them to Last9 using Docker Compose for easy orchestration.

## Supported Versions

- Oracle XE 21c (as used in this example)

## Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop)
- [Docker Compose](https://docs.docker.com/compose/)

## Quick Start

1. **Start the services:**

   ```sh
   docker-compose up --build
   ```

   This will:
   - Build an Oracle XE image with seeded data and required privileges for monitoring.
   - Start Oracle XE and the OpenTelemetry Collector.

2. **Verify Oracle XE is running:**

   - Oracle XE SQL: [localhost:1521](localhost:1521)
   - Oracle EM Express: [localhost:5500](localhost:5500/em)

3. **Check OpenTelemetry Collector:**

   - The collector is configured to scrape Oracle metrics every 60 seconds and export them to both the debug exporter and Last9 via OTLP.
   - The OTLP exporter is configured with:
     - **Endpoint:** Last9 OpenTelemetry endpoint.
     - **Authorization header:** Authorization header for your Last9 OpenTelemetry endpoint.
   - You can modify `otel-collector-config.yaml` to change metric collection, exporters, or authentication details.
   - For the full list of available metrics and configuration options, see the [oracledbreceiver documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/oracledbreceiver/documentation.md) (also linked in the config file).

## Database Details

- **Service Name:** `XEPDB1`
- **User:** `last9`
- **Password:** `last9`
- **Sample Table:** `customers`

## File Overview

- **Dockerfile**: Builds the Oracle XE image, seeds a sample schema, and grants required privileges for metrics collection.
- **docker-compose.yml**: Orchestrates Oracle XE and the OpenTelemetry Collector.
- **seed.sql**: Seeds the database with a sample `customers` table and data.
- **grant_metrics_privs.sql**: Creates the `last9` user and grants necessary privileges for metrics scraping.
- **otel-collector-config.yaml**: Configures the OpenTelemetry Collector to scrape Oracle metrics and export them to Last9.

## Customization

- Edit `seed.sql` to change or add sample data.
- Edit `otel-collector-config.yaml` to change metric collection, exporters, or authentication.

## Stopping the Stack

```sh
docker-compose down
```

## Troubleshooting

1. **Oracle XE issues:**
   ```sh
   docker logs oracledb
   docker exec -it oracledb bash
   # Use sqlplus inside the container for further debugging
   ```

2. **OpenTelemetry Collector issues:**
   ```sh
   docker logs otel-collector
   ```

3. **Database connectivity:**
   - Ensure ports 1521 and 5500 are not blocked by your firewall.
   - Check that the `last9` user exists and has the correct privileges (see `grant_metrics_privs.sql`).

4. **Permissions**

If you see permissions error, make sure to run following.

```
docker exec -it oracledb bash
sqlplus sys/oracle@localhost:1521/XEPDB1 as sysdba
GRANT CREATE SESSION TO last9;
GRANT CREATE SESSION TO last9;
GRANT CONNECT, SELECT_CATALOG_ROLE TO last9;
GRANT SELECT ON V_$SESSION TO last9;
GRANT SELECT ON V_$SYSSTAT TO last9;
GRANT SELECT ON V_$SYSTEM_EVENT TO last9;
GRANT SELECT ON V_$PROCESS TO last9;
GRANT SELECT ON V_$RESOURCE_LIMIT TO last9;
GRANT SELECT ON V_$SQL TO last9;
GRANT SELECT ON V_$SQLAREA TO last9;
GRANT SELECT ON V_$SQLSTATS TO last9;
GRANT SELECT ON V_$INSTANCE TO last9;
GRANT SELECT ON DBA_TABLESPACES TO last9;
GRANT SELECT ON DBA_DATA_FILES TO last9;
GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO last9;
```

---

For advanced configuration, refer to the official [OpenTelemetry Collector documentation](https://opentelemetry.io/docs/collector/), [Oracle XE documentation](https://docs.oracle.com/en/database/oracle/oracle-database/21/xeinl/index.html), and the [oracledbreceiver documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/oracledbreceiver/documentation.md).