# MSSQL + OTel Collector — Error Log + Query Store

Tests that the OTel Collector correctly reads MSSQL ERRORLOG and collects Query Store metrics.

## What it tests

- **ERRORLOG collection**: Filelog receiver reads SQL Server error log entries
- **Query Store metrics**: `sqlserver` receiver collects query performance data
- **Host metrics**: CPU, memory, disk, network

## Quick start

```bash
# Start MSSQL (seeds 100K rows via init container)
docker compose up -d

# Wait for init to complete
docker logs mssql-init -f

# Generate slow queries (populates Query Store)
docker compose --profile generate up slow-query-generator

# Check collector output
docker logs mssql-otel-collector 2>&1 | grep "LogRecord\|sqlserver"

# Clean up
docker compose down -v
```

## Note on slow query detection

SQL Server does not have a dedicated slow query log file. Instead:
- **Query Store** captures query performance data (duration, CPU, reads) which the `sqlserver` receiver collects as metrics
- **ERRORLOG** captures operational events (errors, login failures, deadlocks)
- For real-time slow query alerting, use Last9 to set thresholds on Query Store metrics
