# Quick Start: Oracle 19c Monitoring on Mac

**Test Oracle database monitoring locally with Docker before deploying to production**

## Prerequisites

1. **Docker Desktop for Mac** (https://www.docker.com/products/docker-desktop)
   - Minimum: 8GB RAM, 50GB disk
   - Recommended: 16GB RAM, 100GB disk

2. **Oracle Container Registry Account** (free)
   - Sign up: https://container-registry.oracle.com
   - Accept Oracle Database Enterprise Edition terms

3. **Last9 Account**
   - Sign up: https://app.last9.io
   - Get API token from Settings → API Tokens

## 5-Minute Setup

### Step 1: Oracle Container Registry Login

```bash
# Login to Oracle registry
docker login container-registry.oracle.com

# Username: your-email@example.com
# Password: your-password
```

### Step 2: Configure Environment

```bash
# Navigate to directory
cd docker-compose-test/

# Copy environment template
cp .env.example .env

# Edit .env file
nano .env  # or use your favorite editor
```

**Required changes in .env:**
```bash
# Change passwords
ORACLE_PWD=YourStrongPassword123
ORACLE_MONITOR_PASSWORD=MonitorPassword456

# Add your Last9 token
LAST9_AUTH_HEADER=Basic YOUR_BASE64_TOKEN_HERE
```

### Step 3: Start the Stack

```bash
# Start Oracle + Collector
docker-compose up -d

# This will:
# 1. Pull Oracle 19c image (~8GB, takes time on first run)
# 2. Initialize Oracle database (2-3 minutes)
# 3. Create monitoring user automatically
# 4. Start OpenTelemetry Collector
```

### Step 4: Wait for Oracle

```bash
# Watch Oracle initialization
docker-compose logs -f oracle

# Look for this message:
# "#########################"
# "DATABASE IS READY TO USE!"
# "#########################"
```

### Step 5: Verify Monitoring

```bash
# Check collector health
curl http://localhost:13133

# Check Oracle metrics are being collected
curl http://localhost:8888/metrics | grep oracledb

# Should see metrics like:
# oracledb_sessions{status="ACTIVE"} 5
# oracledb_cpu_time 12345
# oracledb_physical_reads 67890
```

### Step 6: Verify in Last9

1. Open https://app.last9.io
2. Navigate to **Metrics** or **Dashboards**
3. Query: `oracledb_sessions`
4. Metrics should appear within 2-3 minutes

## Common Commands

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f oracle
docker-compose logs -f otel-collector
docker-compose logs -f oracle-setup

# Check service status
docker-compose ps

# Restart collector
docker-compose restart otel-collector

# Connect to Oracle
docker-compose exec oracle sqlplus system/YourPassword@ORCL as sysdba

# Test monitoring user
docker-compose exec oracle sqlplus last9_monitor/MonitorPassword@ORCL

# Stop everything
docker-compose down

# Stop and delete all data (start fresh)
docker-compose down -v
```

## Verification Tests

### Test 1: Oracle Connection

```bash
docker-compose exec oracle sqlplus -s system/YourPassword@ORCL as sysdba <<EOF
SELECT 'Oracle is running!' FROM DUAL;
EXIT;
EOF
```

### Test 2: Monitoring User Permissions

```bash
docker-compose exec oracle sqlplus -s last9_monitor/MonitorPassword@ORCL <<EOF
SELECT COUNT(*) AS metric_count FROM V\$SYSSTAT WHERE ROWNUM <= 10;
EXIT;
EOF
```

### Test 3: Collector Metrics

```bash
# Get metrics snapshot
curl -s http://localhost:8888/metrics > metrics.txt

# Check for Oracle metrics
grep "oracledb" metrics.txt | head -20

# Check export success
grep "otelcol_exporter_sent_metric_points" metrics.txt
```

## Troubleshooting

### Oracle Won't Start

**Symptom:** Container keeps restarting

```bash
# Check logs
docker-compose logs oracle | tail -100

# Common issues:
# 1. Not enough memory
#    Solution: Docker Desktop → Preferences → Resources → 8GB RAM

# 2. Not enough disk
#    Solution: docker system prune -a (frees up space)

# 3. Port 1521 already in use
#    Solution: Stop other Oracle instances or change port
```

### Monitoring User Not Created

**Symptom:** Collector can't connect to Oracle

```bash
# Check oracle-setup logs
docker-compose logs oracle-setup

# Manually create user
docker-compose exec oracle sqlplus system/YourPassword@ORCL as sysdba @/opt/oracle/scripts/setup/create-user.sql

# Verify user exists
docker-compose exec oracle sqlplus -s system/YourPassword@ORCL as sysdba <<EOF
SELECT username FROM dba_users WHERE username = 'LAST9_MONITOR';
EOF
```

### No Metrics in Last9

**Symptom:** Metrics not appearing in Last9 dashboard

```bash
# 1. Check collector can reach Oracle
docker-compose exec otel-collector wget -qO- http://oracle:1521 && echo "Oracle reachable" || echo "Cannot reach Oracle"

# 2. Check collector logs for errors
docker-compose logs otel-collector | grep -i error

# 3. Verify Last9 auth header
# Edit .env and ensure LAST9_AUTH_HEADER is correct (no extra spaces/quotes)

# 4. Test local metrics first
curl http://localhost:8888/metrics | grep oracledb_sessions

# 5. Restart collector
docker-compose restart otel-collector
```

### High CPU/Memory Usage

**Symptom:** Docker using too many resources

```bash
# Check resource usage
docker stats

# Reduce Oracle memory in docker-compose.yml:
# INIT_SGA_SIZE: 1024  # Reduce from 2048
# INIT_PGA_SIZE: 256   # Reduce from 512

# Restart
docker-compose down
docker-compose up -d
```

## Accessing Services

- **Oracle SQL*Plus**: `docker-compose exec oracle sqlplus system/password@ORCL as sysdba`
- **Oracle Enterprise Manager**: http://localhost:5500/em
- **Collector Health**: http://localhost:13133
- **Collector Metrics**: http://localhost:8888/metrics
- **Collector zpages**: http://localhost:55679/debug/tracez

## Cleanup

```bash
# Stop services (keep data)
docker-compose down

# Stop and delete data
docker-compose down -v

# Remove Oracle image (free up 8GB)
docker rmi container-registry.oracle.com/database/enterprise:19.3.0.0

# Free up Docker space
docker system prune -a
```

## Next Steps

Once local testing works:

1. **Review Production Setup**: See `../README.md` for production deployment
2. **Create Database Scripts**: Use `../database-setup/*.sql` for production Oracle
3. **Configure Air-Gapped**: Use `../agent-mode/config-oracle-agent.yaml` for datacenter
4. **Import Dashboards**: Use `../dashboards/*.json` in Last9
5. **Set Up Alerts**: Configure thresholds in Last9

## Performance Notes

**Docker Oracle is for TESTING ONLY**

- ✅ Good for: Development, testing, POC
- ❌ Not for: Production, load testing, benchmarks

**Resource Usage:**
- Idle Oracle: ~2GB RAM, 5-10% CPU
- Under load: ~4GB RAM, 30-50% CPU
- Disk: 10-20GB (grows over time)

**Production Considerations:**
- Use dedicated Oracle server (physical or VM)
- Proper backup strategy
- High availability setup (RAC)
- Performance tuning
- Security hardening

---

**Questions?** Check `../README.md` for complete documentation.
