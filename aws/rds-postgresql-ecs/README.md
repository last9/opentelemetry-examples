# RDS PostgreSQL Monitoring with OpenTelemetry

Complete monitoring solution for AWS RDS PostgreSQL using OpenTelemetry, providing **Datadog DBM feature parity** with three layers of metrics:

1. **PostgreSQL Infrastructure Metrics** - Tables, indexes, connections, transactions
2. **Query-Level Performance Metrics** - Individual query stats from pg_stat_statements
3. **RDS Host Metrics** - CPU, memory, IOPS, storage from CloudWatch

All metrics exported to Last9 (or any OTLP endpoint) via OpenTelemetry.

---

## 🎯 What You Get

✅ **57 metrics** across infrastructure, query, and host levels
✅ **Query performance monitoring** with SQL text and execution stats
✅ **RDS CloudWatch metrics** (CPU, memory, IOPS, latency, storage)
✅ **PostgreSQL 11-15 compatible** with auto-detection
✅ **Datadog DBM parity** at ~10% of the cost

---

## 📊 What Each Collector Does

This solution uses **3 separate collectors** to provide complete monitoring:

| Collector | What It Collects | Source | Metrics Count |
|-----------|-----------------|--------|---------------|
| **OTEL Collector** | PostgreSQL infrastructure metrics (connections, transactions, tables, indexes, WAL, BGWriter) | PostgreSQL receiver | 34 metrics |
| **DBM Collector** | Query-level performance (individual query stats, execution time, I/O, buffer cache) | pg_stat_statements | 9 metrics |
| **CloudWatch Collector** | RDS host metrics (CPU, memory, IOPS, storage, latency, network) | AWS CloudWatch API | 14 metrics |

**Total: 57 metrics** providing complete visibility from infrastructure to query level.

---

## 📋 Prerequisites

Before starting, ensure you have:

| Requirement | Details |
|-------------|---------|
| **RDS PostgreSQL** | Version 11+ running on AWS RDS |
| **AWS Access** | Credentials with RDS and CloudWatch permissions |
| **Last9 Account** | OTLP endpoint and authentication token |
| **Docker** | For running the collectors |
| **Network Access** | Collectors must reach RDS endpoint |

---

## 🚀 Quick Start - Docker Deployment (Tested)

This guide uses **Docker** for local or VM-based deployment. This is the tested and verified method.

> **Note**: CloudFormation and CDK templates are included in the repository but have not been tested yet. Use Docker deployment for production-ready setup.

```bash
# 1. Clone the repository
cd aws/rds-postgresql-ecs

# 2. Copy environment template
cp .env.example .env

# 3. Edit .env with your credentials (see configuration section below)
nano .env  # or use your preferred editor

# 4. Build Docker images
docker build -f Dockerfile -t postgresql-collector:latest .
docker build -f Dockerfile.dbm -t dbm-collector:latest .
docker build -f Dockerfile.cloudwatch -t cloudwatch-collector:latest .

# 5. Start collectors
# OTEL Collector - PostgreSQL infrastructure metrics
docker run -d \
  --name postgresql-collector \
  -p 13133:13133 \
  -p 8888:8888 \
  -v $(pwd)/config/otel-collector-config.yaml:/etc/otel/config.yaml:ro \
  --env-file .env \
  otel/opentelemetry-collector-contrib:0.142.0 \
  --config=/etc/otel/config.yaml

# DBM Collector - Query-level metrics
docker run -d \
  --name dbm-collector \
  --env-file .env \
  -e OUTPUT_FORMAT=otlp \
  -e COLLECTION_INTERVAL=30 \
  dbm-collector:latest

# CloudWatch Collector - RDS host metrics
docker run -d \
  --name cloudwatch-collector \
  --env-file .env \
  -e COLLECTION_INTERVAL=60 \
  cloudwatch-collector:latest

# 6. Verify health
curl http://localhost:13133/health

# 7. Check logs
docker logs postgresql-collector
docker logs dbm-collector
docker logs cloudwatch-collector

# 8. Verify metrics in Last9
# Search for: postgresql.*, postgresql_dbm_*, rds_*
```

---

## 📖 Step-by-Step Deployment Guide

### Step 1: Prepare Your RDS Instance

#### 1.1 Configure RDS Parameter Group

Modify your RDS parameter group to enable monitoring:

```bash
# Via AWS CLI
aws rds modify-db-parameter-group \
  --db-parameter-group-name your-parameter-group \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=pg_stat_statements.max,ParameterValue=10000,ApplyMethod=pending-reboot" \
    "ParameterName=track_io_timing,ParameterValue=1,ApplyMethod=immediate" \
    "ParameterName=track_activity_query_size,ParameterValue=4096,ApplyMethod=immediate" \
    "ParameterName=log_min_duration_statement,ParameterValue=100,ApplyMethod=immediate"

# Reboot RDS instance to apply parameter changes
aws rds reboot-db-instance --db-instance-identifier your-rds-instance
```

Or via AWS Console:
1. Go to RDS → Parameter Groups
2. Select your parameter group
3. Edit parameters:
   - `shared_preload_libraries` = `pg_stat_statements` (requires reboot)
   - `pg_stat_statements.track` = `all`
   - `pg_stat_statements.max` = `10000` (requires reboot)
   - `track_io_timing` = `on`
   - `track_activity_query_size` = `4096`
   - `log_min_duration_statement` = `100`
4. Save changes and reboot your RDS instance

#### 1.2 Create Monitoring User

Connect to your PostgreSQL database and create the monitoring user:

```sql
-- Connect as master user
psql -h your-rds-endpoint.region.rds.amazonaws.com -U postgres -d postgres

-- Create monitoring user
CREATE USER otel_monitor WITH PASSWORD 'your_secure_password_here';

-- Grant necessary permissions
GRANT pg_monitor TO otel_monitor;  -- PostgreSQL 10+
GRANT rds_superuser TO otel_monitor;  -- RDS specific

-- Enable pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant access to pg_stat_statements
GRANT SELECT ON pg_stat_statements TO otel_monitor;

-- Grant database access
GRANT CONNECT ON DATABASE your_database TO otel_monitor;
GRANT USAGE ON SCHEMA public TO otel_monitor;

-- Create monitoring schema (for DBM collector)
CREATE SCHEMA IF NOT EXISTS otel_monitor;
GRANT USAGE ON SCHEMA otel_monitor TO otel_monitor;
GRANT CREATE ON SCHEMA otel_monitor TO otel_monitor;

-- Verify permissions
\du otel_monitor
```

For a complete setup script, see: [scripts/setup-db-user.sql](scripts/setup-db-user.sql)

#### 1.3 Configure Security Group

Add inbound rule to allow collector access:

```bash
# Get your security group ID
aws rds describe-db-instances \
  --db-instance-identifier your-rds-instance \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId'

# Add inbound rule (replace with your collector security group ID or CIDR)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 5432 \
  --source-group <collector-security-group-id>
```

Or via AWS Console:
1. RDS → Databases → Select your instance
2. Click on VPC security group
3. Add inbound rule: Type=PostgreSQL, Port=5432, Source=Collector SG

---

### Step 2: Configure Last9 Credentials

#### 2.1 Get Last9 OTLP Endpoint and Token

1. Log in to your Last9 account
2. Navigate to **Settings → Integrations**
3. Copy your **OTLP Endpoint** (e.g., `YOUR_LAST9_ENDPOINT`)
4. Copy or create an **Authentication Token**
5. Encode credentials: `echo -n "username:token" | base64`

---

### Step 3: Configure Environment Variables

Create your `.env` file with the required credentials:

```bash
# Copy template
cp .env.example .env

# Edit with your actual values
nano .env
```

Your `.env` should contain:
```bash
# PostgreSQL Connection
PG_ENDPOINT=your-rds-endpoint.region.rds.amazonaws.com
PG_PORT=5432
PG_USERNAME=otel_monitor
PG_PASSWORD=your_secure_password_here
PG_DATABASE=your_database

# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
RDS_INSTANCE_ID=your-rds-instance

# Last9 Configuration
LAST9_OTLP_ENDPOINT=YOUR_LAST9_ENDPOINT
LAST9_AUTH_HEADER=Basic YOUR_BASE64_CREDENTIALS

# Environment
ENVIRONMENT=prod
```

---

### Step 4: Deploy Collectors with Docker

```bash
# 1. Create .env file (use the template)
cp .env.example .env

# 2. Edit .env with your actual credentials
# Use your favorite editor to fill in:
# - PG_ENDPOINT, PG_USERNAME, PG_PASSWORD, PG_DATABASE
# - AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# - RDS_INSTANCE_ID
# - LAST9_OTLP_ENDPOINT, LAST9_AUTH_HEADER
nano .env

# 3. Build Docker images
docker build -f Dockerfile -t postgresql-collector:latest .
docker build -f Dockerfile.dbm -t dbm-collector:latest .
docker build -f Dockerfile.cloudwatch -t cloudwatch-collector:latest .

# 4. Start OTEL Collector (PostgreSQL infrastructure metrics)
docker run -d \
  --name postgresql-collector \
  -p 13133:13133 \
  -p 8888:8888 \
  -p 55679:55679 \
  -v $(pwd)/config/otel-collector-config.yaml:/etc/otel/config.yaml:ro \
  --env-file .env \
  otel/opentelemetry-collector-contrib:0.142.0 \
  --config=/etc/otel/config.yaml

# 5. Start DBM Collector (Query-level metrics)
docker run -d \
  --name dbm-collector \
  --env-file .env \
  -e OUTPUT_FORMAT=otlp \
  -e COLLECTION_INTERVAL=30 \
  dbm-collector:latest

# 6. Start CloudWatch Collector (RDS host metrics)
docker run -d \
  --name cloudwatch-collector \
  --env-file .env \
  -e COLLECTION_INTERVAL=60 \
  cloudwatch-collector:latest

# 7. Verify all containers are running
docker ps | grep -E "postgresql-collector|dbm-collector|cloudwatch-collector"

# 8. Check logs for any errors
docker logs postgresql-collector
docker logs dbm-collector
docker logs cloudwatch-collector
```

---

### Step 5: Verify Deployment

#### 5.1 Check Collector Health

```bash
# Check OTEL Collector health endpoint
curl http://localhost:13133/health

# Expected response:
# {"status":"Server available","upSince":"...","uptime":"..."}

# Check all container statuses
docker ps --format "table {{.Names}}\t{{.Status}}"

# View recent logs from each collector
docker logs --tail 50 postgresql-collector
docker logs --tail 50 dbm-collector
docker logs --tail 50 cloudwatch-collector
```

#### 5.2 Verify Metrics in Last9

1. Log in to Last9
2. Navigate to **Explore → Metrics**
3. Search for:
   - `postgresql.*` - Infrastructure metrics (34 metrics)
   - `postgresql_dbm_*` - Query-level metrics (9 metrics)
   - `rds_*` - CloudWatch host metrics (14 metrics)

Example queries:
```promql
# CPU Utilization
rds_cpu_utilization_percent{db_instance_id="your-rds-instance"}

# Top 10 slowest queries
topk(10, postgresql_dbm_query_time_milliseconds_total)

# Database connections
postgresql_backends{database="your_database"}

# Buffer cache hit ratio
sum(postgresql_dbm_query_buffer_hits_total) /
(sum(postgresql_dbm_query_buffer_hits_total) + sum(postgresql_dbm_query_buffer_reads_total)) * 100
```

---

## 📊 Metrics Reference

### 1. PostgreSQL Infrastructure Metrics (34 metrics)

**Source**: OpenTelemetry PostgreSQL Receiver

| Metric | Description | Labels |
|--------|-------------|--------|
| `postgresql.backends` | Active connections | `database`, `state` |
| `postgresql.commits` | Transaction commits | `database` |
| `postgresql.rollbacks` | Transaction rollbacks | `database` |
| `postgresql.operations` | Row operations (ins/upd/del) | `database`, `table`, `operation` |
| `postgresql.rows` | Live/dead rows | `database`, `table`, `state` |
| `postgresql.blocks_read` | Block I/O | `database`, `table`, `source` |
| `postgresql.db_size` | Database size | `database` |
| `postgresql.table.size` | Table size | `database`, `table` |
| `postgresql.index.scans` | Index scans | `database`, `table`, `index` |
| `postgresql.bgwriter.*` | Background writer stats | - |
| `postgresql.wal.age` | WAL age | `database` |

### 2. Query-Level DBM Metrics (9 metrics)

**Source**: Custom DBM Collector (pg_stat_statements)

| Metric | Description | Labels |
|--------|-------------|--------|
| `postgresql_dbm_query_calls_total` | Query execution count | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_time_milliseconds_total` | Total execution time | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_rows_total` | Rows returned/affected | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_buffer_hits_total` | Buffer cache hits | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_buffer_reads_total` | Disk reads | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_io_read_time_milliseconds_total` | I/O read time | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_io_write_time_milliseconds_total` | I/O write time | `database`, `username`, `query_signature` |
| `postgresql_dbm_query_info` | Query text mapping | `database`, `username`, `query_signature`, `query` |
| `postgresql_dbm_active_queries` | Currently active queries | `database` |

### 3. RDS CloudWatch Metrics (14 metrics)

**Source**: Custom CloudWatch Collector

| Metric | Description | Labels |
|--------|-------------|--------|
| `rds_cpu_utilization_percent` | CPU usage | `db_instance_id`, `cloud_region` |
| `rds_memory_freeable_bytes` | Available memory | `db_instance_id`, `cloud_region` |
| `rds_memory_swap_usage_bytes` | Swap usage | `db_instance_id`, `cloud_region` |
| `rds_storage_free_bytes` | Free storage space | `db_instance_id`, `cloud_region` |
| `rds_iops_read_per_second` | Read IOPS | `db_instance_id`, `cloud_region` |
| `rds_iops_write_per_second` | Write IOPS | `db_instance_id`, `cloud_region` |
| `rds_throughput_read_bytes_per_second` | Read throughput | `db_instance_id`, `cloud_region` |
| `rds_throughput_write_bytes_per_second` | Write throughput | `db_instance_id`, `cloud_region` |
| `rds_latency_read_seconds` | Read latency | `db_instance_id`, `cloud_region` |
| `rds_latency_write_seconds` | Write latency | `db_instance_id`, `cloud_region` |
| `rds_connections_ratio` | Database connections | `db_instance_id`, `cloud_region` |
| `rds_network_receive_throughput_bytes_per_second` | Network RX | `db_instance_id`, `cloud_region` |
| `rds_network_transmit_throughput_bytes_per_second` | Network TX | `db_instance_id`, `cloud_region` |
| `rds_disk_queue_depth_ratio` | Disk queue depth | `db_instance_id`, `cloud_region` |

---

## 🔧 Configuration

### Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `PG_ENDPOINT` | RDS endpoint hostname | Yes | - |
| `PG_PORT` | PostgreSQL port | No | `5432` |
| `PG_USERNAME` | Monitoring user | Yes | - |
| `PG_PASSWORD` | Monitoring password | Yes | - |
| `PG_DATABASE` | Database name | Yes | - |
| `AWS_REGION` | AWS region | Yes | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | AWS access key | Yes* | - |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | Yes* | - |
| `AWS_SESSION_TOKEN` | AWS session token | No | - |
| `RDS_INSTANCE_ID` | RDS instance identifier | Yes | - |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint | Yes | - |
| `LAST9_AUTH_HEADER` | Last9 auth header | Yes | - |
| `ENVIRONMENT` | Environment tag | No | `dev` |
| `COLLECTION_INTERVAL` | Collection interval (seconds) | No | `30` |

*Not required if using IAM roles (ECS task role)

---

## 🐛 Troubleshooting

### Problem: Collector not starting

**Symptoms**: ECS task keeps restarting

**Solutions**:
```bash
# Check logs
aws logs tail /ecs/postgresql-collector/prod --since 1h

# Common issues:
# 1. Invalid credentials → Check Secrets Manager
# 2. Network connectivity → Check security groups
# 3. Parameter group → Verify pg_stat_statements is enabled
```

### Problem: No metrics in Last9

**Solutions**:
```bash
# 1. Verify collector health
curl http://localhost:13133/health

# 2. Check OTLP endpoint
curl -v YOUR_LAST9_ENDPOINT/health

# 3. Verify auth header
echo "YOUR_BASE64_STRING" | base64 -d

# 4. Check collector logs
docker logs postgresql-collector | grep -i error
```

### Problem: pg_stat_statements returns empty

**Solutions**:
```sql
-- 1. Verify extension exists
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';

-- 2. Check parameter
SHOW shared_preload_libraries;
-- Should show: pg_stat_statements

-- 3. Check stats
SELECT count(*) FROM pg_stat_statements;
-- Should show > 0

-- 4. If empty, reboot RDS instance after setting shared_preload_libraries
```

### Problem: CloudWatch metrics not appearing

**Solutions**:
```bash
# 1. Verify AWS credentials
aws sts get-caller-identity

# 2. Test CloudWatch access
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=your-rds-instance \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 3600 \
  --statistics Average

# 3. Check collector logs
docker logs cloudwatch-collector
```

---

## 📚 Additional Resources

- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [PostgreSQL Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/postgresqlreceiver)
- [AWS RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [Last9 Documentation](https://docs.last9.io)
- [Datadog DBM Reference](https://docs.datadoghq.com/database_monitoring/setup_postgres/rds/) (for feature comparison)

---

## 🤝 Support

For issues or questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review [SPEC.md](SPEC.md) for technical details
3. Open an issue in the repository

---

## 📝 License

This example is provided as-is for reference and educational purposes.
