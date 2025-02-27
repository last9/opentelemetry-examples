# Monitoring Postgres with OpenTelemetry and Last9

A guide for setting up Postgres monitoring using OpenTelemetry Collector with Last9. It collects Postgres metrics, and logs from Postgres and sends them to Last9.

## Installation

### 1. Prerequisites

Ensure Docker and Docker Compose are installed on your system:

```bash
# Check Docker installation
docker --version

# Check Docker Compose installation
docker compose version
```

### 2. Configure OpenTelemetry Collector

The setup uses the otel-collector-config.yaml file which defines:
Prometheus receiver for scraping Postgres metrics
Processors for batch processing and resource detection
Last9 exporter configuration
Before proceeding, update the Last9 authorization token:

```bash
# Edit the config file
nano otel-collector-config.yaml
```

In the `exporters` section, replace <LAST9_OTLP_AUTH_HEADER> with your actual Last9 authorization auth header and <LAST9_OTLP_ENDPOINT> with the endpoint URL. You can get the auth header from Last9 Integrations.

### 3. Configure Postgres Exporter

Update the environment variables in docker-compose.yaml:

```yaml
Replace the following placeholders with your actual Postgres database information:
<DB_HOST>: Your Postgres database host
<DB_NAME>: Your Postgres database name
<DB_USER>: Your Postgres database username
<DB_PASSWORD>: Your Postgres database password
```

### 4. Start the Monitoring Stack

```bash
docker compose -f docker-compose.yaml up -d
```

This starts:
- Postgres Exporter that collects metrics from your Postgres database
- OpenTelemetry Collector that receives metrics from Postgres Exporter and forwards them to Last9.

### Understanding the Setup

#### Postgres Exporter

The Postgres Exporter connects to your Postgres database and exposes metrics in Prometheus format. It's configured to:
- Connect to your database using the provided credentials
- Use custom queries defined in queries.yaml
- Expose metrics on port 9187

#### Custom Queries

The queries.yaml file defines custom metrics to collect from Postgres. The example includes a slow_queries metric that:
- Identifies queries running longer than 1 minute
- Collects detailed information about these queries including:
  - Process ID
  - Database name
  - Username
  - Query text
  - Execution time
  - Wait events
  - Blocking processes

#### OpenTelemetry Collector

The OpenTelemetry Collector is configured to:
- Scrape metrics from Postgres Exporter every 60 seconds
- Add resource attributes like database name and environment
- Process metrics in batches
- Export metrics to Last9 using OTLP protocol

### Verification

Verify the containers are running:

```bash
docker ps
```

Check Postgres Exporter metrics:

```bash
curl http://localhost:9187/metrics
```

Check OpenTelemetry Collector logs:

```bash
docker logs otel-collector
```

### Troubleshooting

1. Container issues:

```bash
# Check container status
docker ps -a

# View container logs
docker logs postgres-exporter
docker logs otel-collector
```

2. Connection issues:

```bash
docker logs postgres-exporter
```
3. OpenTelemetry Collector issues:

```bash
# Check configuration
docker exec otel-collector cat /etc/otel/collector/config.yaml

# Restart collector
docker compose restart otel-collector
```

### Extending the Configuration

#### Adding More Custom Queries

You can extend queries.yaml to monitor additional aspects of your Postgres database:
- Connection metrics
- Table statistics
- Index usage
- Buffer cache hit ratio
- Replication lag

#### Monitoring Multiple Databases

To monitor multiple Postgres databases:
- Create separate instances of Postgres Exporter in your docker-compose.yaml
- Configure each with different database credentials
- Update the OpenTelemetry Collector configuration to scrape metrics from all exporters

## Required Postgres Permissions

The Postgres Exporter needs specific permissions to access system catalog tables and views, especially for the custom queries defined in `queries.yaml`. For the `slow_queries` query, which accesses `pg_stat_activity`, you need to create a dedicated monitoring user with appropriate permissions:

```sql
-- Create a dedicated user for monitoring
CREATE USER postgres_exporter WITH PASSWORD 'your_secure_password';

-- Grant permissions required for monitoring
GRANT pg_monitor TO postgres_exporter;

-- If using PostgreSQL version earlier than 10, you'll need these specific grants instead:
-- GRANT SELECT ON pg_stat_activity TO postgres_exporter;
-- GRANT SELECT ON pg_stat_replication TO postgres_exporter;
-- GRANT SELECT ON pg_stat_database TO postgres_exporter;
```

When configuring the Postgres Exporter in your `docker-compose.yaml`, make sure to use this dedicated monitoring user:

```yaml
environment:
  - DATA_SOURCE_URI=<DB_HOST>/<DB_NAME>
  - DATA_SOURCE_USER=<DB_USER>
  - DATA_SOURCE_PASS=<DB_PASSWORD>
```

### Additional Permissions for Custom Metrics

If you add more custom queries to `queries.yaml` that access other system tables or views, you may need to grant additional permissions. For example:

- For table statistics: `GRANT SELECT ON pg_statio_user_tables TO postgres_exporter;`
- For index usage: `GRANT SELECT ON pg_stat_user_indexes TO postgres_exporter;`
- For replication monitoring: `GRANT SELECT ON pg_stat_replication TO postgres_exporter;`

Always follow the principle of least privilege by granting only the permissions necessary for monitoring purposes.
