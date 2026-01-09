# RDS PostgreSQL Monitoring with OpenTelemetry

Complete monitoring for AWS RDS PostgreSQL with OpenTelemetry - 57 metrics exported to Last9.

**Three layers of monitoring:**
- **PostgreSQL Infrastructure** (34 metrics) - Connections, transactions, tables, indexes
- **Query Performance** (9 metrics) - Execution time, I/O, buffer cache from pg_stat_statements
- **RDS Host** (14 metrics) - CPU, memory, IOPS, storage from CloudWatch

---

## Quick Start

Choose your deployment method:

### Option 1: Quick Setup (Recommended - CloudFormation)

**Automated deployment in 4 steps (~10 minutes):**

```bash
cd aws/rds-postgresql-ecs
cp .env.example .env
# Edit .env with your credentials
./build-and-push-images.sh
./quick-setup.sh
```

👉 **[See Full Quick Setup Guide](QUICK_SETUP.md)** - Step-by-step instructions

**What's automated:**
- Auto-discovers RDS configuration
- Builds and pushes Docker images to ECR
- Deploys CloudFormation stack with ECS Fargate
- Configures security groups and networking
- Sets up all 3 collectors

---

### Option 2: Manual Docker Setup

**For development or custom deployments:**

#### Step 1: Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```bash
# RDS Details
PG_ENDPOINT=your-rds-endpoint.rds.amazonaws.com
PG_PORT=5432
PG_USERNAME=otel_monitor
PG_PASSWORD=your-password
PG_DATABASE=postgres

# AWS Configuration
AWS_REGION=us-east-1
RDS_INSTANCE_ID=your-rds-instance

# Last9 OTLP Configuration
LAST9_OTLP_ENDPOINT=https://your-endpoint.last9.io
LAST9_AUTH_HEADER=Basic <base64-encoded-user:pass>

# Environment
ENVIRONMENT=prod
```

#### Step 2: Create Monitoring User

Run this SQL script as master user:

```bash
psql -h your-rds-endpoint -U postgres -d postgres -f scripts/setup-db-user.sql
```

**What it does:**
- Creates `otel_monitor` user with read-only access
- Grants `pg_monitor` role
- Creates helper functions for monitoring
- Enables `pg_stat_statements` extension

#### Step 3: Build Docker Images

```bash
docker build -f Dockerfile -t postgresql-collector:latest .
docker build -f Dockerfile.dbm -t dbm-collector:latest .
docker build -f Dockerfile.cloudwatch -t cloudwatch-collector:latest .
```

#### Step 4: Start Collectors

**Using Docker Compose:**

```bash
docker-compose up -d
```

**Or manually:**

```bash
# OTEL Collector (PostgreSQL infrastructure metrics)
docker run -d \
  --name postgresql-collector \
  -v $(pwd)/config/otel-collector-config.yaml:/etc/otel/config.yaml:ro \
  --env-file .env \
  otel/opentelemetry-collector-contrib:0.142.0 \
  --config=/etc/otel/config.yaml

# DBM Collector (Query-level metrics)
docker run -d \
  --name dbm-collector \
  --env-file .env \
  dbm-collector:latest

# CloudWatch Collector (RDS host metrics)
docker run -d \
  --name cloudwatch-collector \
  --env-file .env \
  cloudwatch-collector:latest
```

#### Step 5: Verify

```bash
# Check logs
docker logs postgresql-collector
docker logs dbm-collector
docker logs cloudwatch-collector

# Should see:
# "Connected to PostgreSQL"
# "Exported to OTLP: 154 query metrics"
# "Exported 14/17 CloudWatch metrics"
```

---

## Configuration Reference

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PG_ENDPOINT` | RDS endpoint | `mydb.abc123.us-east-1.rds.amazonaws.com` |
| `PG_USERNAME` | Monitoring user | `otel_monitor` |
| `PG_PASSWORD` | User password | `secure-password` |
| `PG_DATABASE` | Database name | `postgres` |
| `RDS_INSTANCE_ID` | RDS instance ID | `my-postgres-db` |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP URL | `https://otlp.last9.io` |
| `LAST9_AUTH_HEADER` | Base64 auth | `Basic base64string` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `COLLECTION_INTERVAL` | `30` | Metrics collection interval (seconds) |
| `ENVIRONMENT` | `prod` | Environment label for metrics |

---

## Verify Metrics in Last9

**1. Login:** https://app.last9.io

**2. Navigate:** Explore → Metrics

**3. Search for these metrics:**

```promql
# PostgreSQL infrastructure
postgresql.backends              # Active connections
postgresql.commits               # Transaction commits
postgresql.db_size               # Database size

# Query performance
postgresql_dbm_query_time_milliseconds_total    # Query execution time
postgresql_dbm_query_calls_total                # Query call count
postgresql_dbm_query_rows_total                 # Rows processed

# RDS host metrics
rds_cpu_utilization             # CPU usage
rds_memory_freeable             # Available memory
rds_storage_free                # Free storage
```

**Example queries:**

```promql
# Database connections
postgresql.backends{database="postgres"}

# Top 10 slowest queries
topk(10, postgresql_dbm_query_time_milliseconds_total)

# CPU utilization
rds_cpu_utilization{db_instance_id="your-rds-instance"}

# Buffer cache hit ratio
sum(postgresql_dbm_query_buffer_hits_total) /
(sum(postgresql_dbm_query_buffer_hits_total) + sum(postgresql_dbm_query_buffer_reads_total)) * 100
```

---

## Enable pg_stat_statements

**Required for query-level metrics.** Enable in RDS parameter group:

```bash
# Get parameter group
aws rds describe-db-instances \
  --db-instance-identifier your-rds-instance \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text

# Modify parameters
aws rds modify-db-parameter-group \
  --db-parameter-group-name your-param-group \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=track_io_timing,ParameterValue=1,ApplyMethod=immediate"

# Reboot RDS (required for shared_preload_libraries)
aws rds reboot-db-instance --db-instance-identifier your-rds-instance
```

---

## Troubleshooting

### No metrics appearing

**Check 1: Container logs**
```bash
docker logs dbm-collector | grep -i error
docker logs cloudwatch-collector | grep -i error
docker logs postgresql-collector | grep -i error
```

**Check 2: Connectivity**
```bash
# Test RDS connection
psql -h $PG_ENDPOINT -U $PG_USERNAME -d $PG_DATABASE -c "SELECT version();"

# Test CloudWatch access
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

**Check 3: Verify Last9 endpoint**
```bash
curl -v $LAST9_OTLP_ENDPOINT/v1/metrics
```

### Common Issues

| Problem | Solution |
|---------|----------|
| Connection timeout | Check RDS security groups allow collector IPs |
| Authentication failed | Verify username/password in `.env` |
| No query metrics | Enable `pg_stat_statements` extension |
| CloudWatch access denied | Add CloudWatch read permissions to AWS credentials |

---

## Cost Estimate

**Quick Setup (CloudFormation/ECS):** ~$16/month
- ECS Fargate (0.25 vCPU, 0.5 GB): $12
- CloudWatch Logs: $2.50
- Secrets Manager: $1.20

**Manual Setup (Docker):** ~$0/month
- Run on existing infrastructure (no additional AWS costs)

---

## Cleanup

**Quick Setup:**
```bash
aws cloudformation delete-stack --stack-name rds-postgresql-monitoring-prod
```

**Manual Setup:**
```bash
docker-compose down
# or
docker stop postgresql-collector dbm-collector cloudwatch-collector
docker rm postgresql-collector dbm-collector cloudwatch-collector
```

---

## Support

- **Quick Setup Issues:** [QUICK_SETUP.md](QUICK_SETUP.md)
- **Technical Details:** [SPEC.md](SPEC.md)
- **Last9 Support:** support@last9.io

---

## What's Collected

### PostgreSQL Infrastructure (34 metrics)
- Connections, transactions, commits, rollbacks
- Tables, indexes, sequential scans
- WAL activity, BGWriter stats
- Database size, deadlocks

### Query Performance (9 metrics)
- Execution time per query
- Call count, rows processed
- Buffer cache hits/reads
- I/O read/write time

### RDS Host (14 metrics)
- CPU utilization and credits
- Memory (freeable, swap)
- Storage (free space)
- IOPS (read/write)
- Network throughput
- Database connections
- Replication lag

---

**That's it! Start monitoring your RDS PostgreSQL database.** 🚀
