# Oracle 19c Database Monitoring with OpenTelemetry

**Production-grade Oracle database monitoring for air-gapped datacenters → AWS → Last9**

## Overview

This example provides comprehensive Oracle 19c database monitoring using OpenTelemetry Collector's Oracle receiver. Designed for both production air-gapped environments and local Docker-based testing on Mac.

### Architecture

```
Oracle 19c Server          Datacenter Gateway       AWS Gateway        Last9
┌─────────────────┐       ┌──────────────┐       ┌──────────┐      ┌───────┐
│ Oracle DB       │       │              │       │          │      │       │
│ + OTel Agent    │──────>│ DC Gateway   │──────>│ AWS GW   │─────>│ OTLP  │
│ (Metrics Only)  │       │ (Aggregator) │       │ (Forwarder)     │       │
└─────────────────┘       └──────────────┘       └──────────┘      └───────┘
```

### Latest Versions

- **OpenTelemetry Collector Contrib**: v0.140.0 (Nov 2025)
- **Oracle Database**: 19c (19.3.0+)
- **Oracle Receiver**: Built into Collector Contrib
- **Monitoring User**: Minimal privileges (SELECT on V$ views)

## Quick Start

### For Production (Windows Server / Linux)

```bash
# 1. Create monitoring user in Oracle
sqlplus / as sysdba @database-setup/create-monitoring-user.sql

# 2. Grant permissions
sqlplus / as sysdba @database-setup/grant-minimal-permissions.sql

# 3. Verify setup
sqlplus / as sysdba @database-setup/verify-setup.sql

# 4. Install OpenTelemetry Collector (if not already installed)
# See ../dotnet-framework-4.8/offline-installation/ for air-gapped setup

# 5. Deploy Oracle monitoring config
cp agent-mode/config-oracle-agent.yaml "C:\Program Files\OpenTelemetry Collector\config.yaml"

# 6. Update credentials in config (use environment variables)
$env:ORACLE_MONITOR_PASSWORD = "your_secure_password"

# 7. Start collector service
Start-Service otelcol-contrib

# 8. Verify metrics
Invoke-WebRequest http://localhost:8888/metrics | Select-String "oracledb"
```

### For Local Testing (Mac with Docker)

```bash
# 1. Navigate to Docker Compose directory
cd docker-compose-test/

# 2. Copy and configure environment variables
cp .env.example .env
# Edit .env with your Last9 credentials

# 3. Start Oracle + Collector stack
docker-compose up -d

# 4. Wait for Oracle to initialize (2-3 minutes)
docker-compose logs -f oracle

# 5. Verify monitoring
curl http://localhost:8888/metrics | grep oracledb

# 6. Check Last9 for metrics
# Metrics should appear within 2 minutes
```

## What Gets Monitored

### Core Database Metrics

✅ **Performance Metrics**
- Consistent gets (logical reads)
- Physical reads/writes
- DB block gets
- Parse counts (hard/soft)
- Execute counts
- I/O wait times

✅ **Session Metrics**
- Active sessions
- Inactive sessions
- Session waits
- Blocking sessions

✅ **Tablespace Metrics**
- Tablespace usage (%)
- Free space
- Datafile sizes
- Growth trends

✅ **Resource Metrics**
- CPU time
- Memory usage
- Process counts
- Resource limits

✅ **Transaction Metrics**
- User commits
- User rollbacks
- Transaction rates

✅ **Parallel Execution**
- Parallel operations
- Downgrade statistics
- DML/DDL parallelization

### System Metrics (when combined with hostmetrics)

✅ **Host Performance**
- CPU utilization
- Memory usage
- Disk I/O
- Network I/O
- Process metrics

## Directory Structure

```
oracle-19c/
├── README.md                          # This file
├── database-setup/
│   ├── create-monitoring-user.sql     # Create last9_monitor user
│   ├── grant-minimal-permissions.sql  # Grant SELECT on V$ views
│   ├── verify-setup.sql               # Verify permissions
│   └── revoke-permissions.sql         # Clean up (if needed)
├── agent-mode/
│   ├── config-oracle-agent.yaml       # Oracle monitoring agent
│   ├── install-oracle-monitoring.ps1  # Windows installation
│   └── install-oracle-monitoring.sh   # Linux installation
├── offline-installation/
│   └── packages/                      # Pre-downloaded collector
├── docker-compose-test/
│   ├── docker-compose.yml             # Full stack for Mac
│   ├── .env.example                   # Environment variables template
│   ├── oracle/
│   │   └── init-scripts/              # Oracle initialization
│   └── otel-collector/
│       └── config.yaml                # Collector config for Docker
└── dashboards/
    ├── oracle-overview.json           # Main dashboard
    ├── oracle-performance.json        # Performance metrics
    └── oracle-sessions.json           # Session monitoring
```

## Security: Monitoring User Setup

### Create User with Minimal Privileges

The monitoring user `last9_monitor` is created with **read-only** access to performance views only. No access to application data.

```sql
-- Create user
CREATE USER last9_monitor IDENTIFIED BY "SecurePassword123";

-- Basic connection
GRANT CREATE SESSION TO last9_monitor;
GRANT CONNECT TO last9_monitor;

-- Read-only catalog access
GRANT SELECT_CATALOG_ROLE TO last9_monitor;

-- Specific V$ views (see grant-minimal-permissions.sql for complete list)
GRANT SELECT ON V_$SESSION TO last9_monitor;
GRANT SELECT ON V_$SYSSTAT TO last9_monitor;
-- ... (30+ views for comprehensive monitoring)
```

**Security Features:**
- ✅ No DML permissions (cannot modify data)
- ✅ No access to application tables
- ✅ Only performance/statistics views
- ✅ Cannot create/drop objects
- ✅ Password stored in environment variables (not config files)

## Configuration

### Agent Mode (On Oracle Server)

Deploy `config-oracle-agent.yaml` on the same server as Oracle database.

**Key Configuration:**

```yaml
receivers:
  oracledb:
    endpoint: localhost:1521
    service: ORCL  # Your Oracle service name
    username: last9_monitor
    password: ${ORACLE_MONITOR_PASSWORD}  # From environment variable
    collection_interval: 60s
```

**Environment Variables:**

```powershell
# Windows
$env:ORACLE_MONITOR_PASSWORD = "SecurePassword123"
[Environment]::SetEnvironmentVariable("ORACLE_MONITOR_PASSWORD", "SecurePassword123", "Machine")

# Linux/Mac
export ORACLE_MONITOR_PASSWORD="SecurePassword123"
```

### Gateway Mode (Datacenter/AWS)

Oracle metrics flow through the same three-tier architecture as application traces:

1. **Agent** (Oracle host) → Collects Oracle metrics
2. **DC Gateway** → Aggregates metrics from multiple databases
3. **AWS Gateway** → Forwards to Last9

See `../dotnet-framework-4.8/gateway-datacenter/` for gateway configurations.

## Docker Compose Setup (Mac Testing)

### Prerequisites

- Docker Desktop for Mac
- 8GB RAM available for Docker
- 50GB disk space

### Services Included

**docker-compose.yml** includes:

1. **Oracle Database** (container-registry.oracle.com/database/enterprise:19.3.0.0)
   - Pre-configured with monitoring user
   - Sample data for testing
   - Health checks

2. **OpenTelemetry Collector** (otel/opentelemetry-collector-contrib:0.140.0)
   - Oracle receiver configured
   - Forwards to Last9
   - Metrics exposed on localhost:8888

### Environment Variables (.env)

```bash
# Oracle Configuration
ORACLE_SID=ORCL
ORACLE_PDB=ORCLPDB1
ORACLE_PWD=YourOraclePassword123
ORACLE_MONITOR_PASSWORD=MonitorPassword123

# Last9 Configuration
LAST9_OTLP_ENDPOINT=https://otlp.last9.io
LAST9_AUTH_HEADER=Basic YOUR_BASE64_TOKEN_HERE

# Resource Attributes
DATACENTER_NAME=docker-test
ENVIRONMENT=development
```

### Usage

```bash
# Start stack
docker-compose up -d

# View logs
docker-compose logs -f

# Check Oracle is ready
docker-compose exec oracle sqlplus system/YourOraclePassword123@ORCL as sysdba

# Check collector metrics
curl http://localhost:8888/metrics | grep oracledb

# Stop stack
docker-compose down

# Clean up (including volumes)
docker-compose down -v
```

## Performance Impact

### Resource Usage

**Per Oracle Agent:**
- CPU: <1% on idle database, 2-5% on busy database
- Memory: 50-100 MB
- Network: 5-20 KB/sec (depends on collection interval)

### Query Impact

The Oracle receiver executes SELECT queries on V$ views:
- Queries are read-only (no DML)
- Minimal impact on database performance
- Typically <0.01% of database load
- Collection interval: 60s (configurable)

**Benchmark:**
```sql
-- Test query performance
SET TIMING ON
SELECT * FROM V_$SYSSTAT;
-- Typical: 10-50ms on 100GB database
```

## Metrics Reference

### Available Metrics

Full list of 50+ metrics available. Key metrics:

| Metric | Description | Unit |
|--------|-------------|------|
| `oracledb.cpu_time` | Total CPU time used | seconds |
| `oracledb.sessions` | Number of sessions by status | sessions |
| `oracledb.physical_reads` | Physical disk reads | reads |
| `oracledb.physical_writes` | Physical disk writes | writes |
| `oracledb.logical_reads` | Logical reads (cache hits) | reads |
| `oracledb.tablespace_usage` | Tablespace usage | bytes |
| `oracledb.user_commits` | Committed transactions | commits |
| `oracledb.user_rollbacks` | Rolled back transactions | rollbacks |
| `oracledb.parse_count.hard` | Hard parses (expensive) | parses |
| `oracledb.parse_count.total` | Total parses | parses |

See [Oracle Receiver Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/oracledbreceiver/documentation.md) for complete list.

## Dashboards

### Pre-built Last9 Dashboards

Import these JSON templates into Last9:

1. **oracle-overview.json** - High-level database health
   - Sessions (active/inactive)
   - CPU and memory usage
   - Tablespace usage
   - Top wait events

2. **oracle-performance.json** - Performance metrics
   - I/O throughput
   - Parse ratios (hard/soft)
   - Cache hit ratios
   - Query execution rates

3. **oracle-sessions.json** - Session monitoring
   - Active sessions by user
   - Blocking sessions
   - Wait events by session
   - Long-running queries

### Custom Queries

Create custom Last9 queries:

```promql
# Sessions over time
oracledb_sessions{status="ACTIVE"}

# Tablespace usage percentage
(oracledb_tablespace_usage / oracledb_tablespace_size) * 100

# Cache hit ratio
(oracledb_consistent_gets - oracledb_physical_reads) / oracledb_consistent_gets * 100

# Transaction rate
rate(oracledb_user_commits[5m])
```

## Troubleshooting

### No Metrics Appearing

```powershell
# 1. Verify Oracle listener is running
lsnrctl status

# 2. Test connection with monitoring user
sqlplus last9_monitor/password@localhost:1521/ORCL

# 3. Check collector logs
Get-Content "C:\ProgramData\OpenTelemetry Collector\logs\otelcol.log" -Tail 50

# 4. Verify collector can reach Oracle
Test-NetConnection -ComputerName localhost -Port 1521

# 5. Check collector metrics endpoint
Invoke-WebRequest http://localhost:8888/metrics | Select-String "oracledb_receiver"
```

### Permission Errors

```sql
-- Verify permissions
SELECT * FROM DBA_SYS_PRIVS WHERE GRANTEE = 'LAST9_MONITOR';
SELECT * FROM DBA_TAB_PRIVS WHERE GRANTEE = 'LAST9_MONITOR';

-- Re-run grant script if needed
@grant-minimal-permissions.sql
```

### High Memory Usage

```yaml
# Add memory limiter to config
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 256  # Adjust based on available memory
```

### Docker Issues (Mac)

```bash
# Oracle taking too long to start
docker-compose logs oracle | grep "DATABASE IS READY TO USE"

# Collector can't connect to Oracle
docker-compose exec collector ping oracle

# Check Oracle health
docker-compose exec oracle /opt/oracle/checkDBStatus.sh
```

## Production Deployment Checklist

- [ ] Monitoring user created with minimal permissions
- [ ] Permissions verified with verify-setup.sql
- [ ] Password stored in environment variable (not config file)
- [ ] Collector installed (offline bundle for air-gapped)
- [ ] Config deployed to collector
- [ ] Firewall allows collector → Oracle (port 1521)
- [ ] Collector service configured for auto-start
- [ ] Oracle metrics visible in Last9 (within 2 minutes)
- [ ] Dashboards imported to Last9
- [ ] Alert thresholds configured
- [ ] Performance impact validated (<1% CPU)
- [ ] Documentation updated for team

## Integration with .NET Application

Oracle database monitoring works alongside .NET application tracing:

```
.NET App (IIS)
  ├─ App traces → Agent → DC Gateway → AWS → Last9
  └─ Calls Oracle DB

Oracle Server
  └─ DB metrics → Agent → DC Gateway → AWS → Last9
```

**Correlation:**
Both application traces and database metrics share the same `service.name` and resource attributes, allowing correlation in Last9.

## Additional Resources

- **Oracle Receiver Docs**: https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/oracledbreceiver
- **Oracle V$ Views**: https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/dynamic-performance-views.html
- **OpenTelemetry Collector**: https://opentelemetry.io/docs/collector/
- **Last9 Documentation**: https://docs.last9.io

## Support

For issues:
1. Check [troubleshooting section](#troubleshooting) above
2. Verify Oracle listener status
3. Check collector logs
4. Test Oracle connectivity
5. Review permissions with verify-setup.sql

---

**Version**: OpenTelemetry Collector Contrib v0.140.0
**Oracle Version**: 19c (19.3.0+)
**Last Updated**: 2025-11-29
