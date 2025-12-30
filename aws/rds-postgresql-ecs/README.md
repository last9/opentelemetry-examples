# RDS PostgreSQL Deep Integration with Last9

Monitor RDS PostgreSQL using OpenTelemetry Collector on ECS Fargate, with full **Datadog DBM feature parity**.

> **Migration Guide**: This integration is designed for customers migrating from [Datadog Database Monitoring for RDS PostgreSQL](https://docs.datadoghq.com/database_monitoring/setup_postgres/rds/). It provides equivalent functionality using OpenTelemetry.

## Features

- **Full pg_stat_* coverage**: connections, transactions, locks, replication, vacuum
- **Query performance monitoring**: pg_stat_statements with normalized queries
- **Wait event monitoring**: real-time blocking detection + historical analysis
- **Host-level RDS metrics**: CPU, memory, IOPS, storage via CloudWatch
- **Log collection**: slow queries (>100ms) and errors via CloudWatch Logs
- **Log-metric correlation**: query fingerprint, connection ID, transaction ID

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Account                          │
│  ┌─────────────────┐      ┌─────────────────────────────┐  │
│  │ RDS PostgreSQL  │◄────►│      ECS Fargate            │  │
│  │                 │      │  ┌───────────────────────┐  │  │
│  │  - Primary      │      │  │  OTEL Collector       │  │  │
│  │  - Replicas     │      │  │  + PostgreSQL Rcvr    │  │  │
│  └────────┬────────┘      │  │  + CloudWatch Rcvr    │  │  │
│           │               │  │  + CloudWatch Logs    │  │  │
│           ▼               │  └───────────┬───────────┘  │  │
│  ┌─────────────────┐      └──────────────┼──────────────┘  │
│  │ CloudWatch      │                     │                  │
│  │ Logs + Metrics  │─────────────────────┤                  │
│  └─────────────────┘                     │                  │
│                                          │ OTLP             │
└──────────────────────────────────────────┼──────────────────┘
                                           ▼
                                   ┌───────────────┐
                                   │    Last9      │
                                   └───────────────┘
```

## Prerequisites

1. **RDS PostgreSQL** instance (version 15+)
2. **ECS Cluster** with Fargate capacity
3. **VPC** with private subnets and NAT gateway
4. **Last9 account** with OTLP endpoint

## Quick Start

### Option 1: CloudFormation

```bash
# Deploy the stack
aws cloudformation deploy \
  --template-file cloudformation/postgresql-collector.yaml \
  --stack-name postgresql-collector-prod \
  --parameter-overrides \
    VpcId=vpc-xxxxxxxxx \
    SubnetIds=subnet-aaa,subnet-bbb \
    Environment=prod \
    Last9OtlpEndpoint=https://otlp.last9.io \
    RDSInstanceId=my-rds-instance \
  --capabilities CAPABILITY_NAMED_IAM

# Update secrets after deployment
aws secretsmanager put-secret-value \
  --secret-id postgresql-collector/prod/last9-auth \
  --secret-string '{"auth_header":"Basic YOUR_AUTH_HEADER"}'

aws secretsmanager put-secret-value \
  --secret-id postgresql-collector/prod/db-credentials \
  --secret-string '{
    "username":"otel_monitor",
    "password":"YOUR_PASSWORD",
    "host":"your-rds-endpoint.region.rds.amazonaws.com",
    "port":5432,
    "dbname":"your_database"
  }'
```

### Option 2: CDK

```bash
cd cdk

# Install dependencies
npm install

# Deploy
cdk deploy \
  -c vpcId=vpc-xxxxxxxxx \
  -c environment=prod \
  -c last9OtlpEndpoint=https://otlp.last9.io \
  -c rdsInstanceId=my-rds-instance
```

### Option 3: Local Testing with Docker Compose

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your values

# Download RDS CA bundle
./scripts/download-rds-ca.sh

# Start collector
docker-compose up -d

# Check health
curl http://localhost:13133/health

# View metrics
curl http://localhost:8888/metrics
```

## Setup Steps

### 1. Configure RDS Parameter Group

Ensure your RDS parameter group has these settings:

| Parameter | Value | Requires Reboot |
|-----------|-------|-----------------|
| `shared_preload_libraries` | `pg_stat_statements` | Yes |
| `pg_stat_statements.track` | `all` | No |
| `pg_stat_statements.max` | `10000` | Yes |
| `track_io_timing` | `on` | No |
| `track_activity_query_size` | `4096` | No |
| `log_min_duration_statement` | `100` | No |

### 2. Create Monitoring User

Connect to your RDS instance and run:

```sql
-- Create monitoring user
CREATE USER otel_monitor WITH PASSWORD 'your_secure_password';

-- Grant pg_monitor role (PostgreSQL 10+)
GRANT pg_monitor TO otel_monitor;

-- Enable pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON pg_stat_statements TO otel_monitor;

-- Grant connect permission
GRANT CONNECT ON DATABASE your_database TO otel_monitor;
GRANT USAGE ON SCHEMA public TO otel_monitor;
```

Full script: [scripts/setup-db-user.sql](scripts/setup-db-user.sql)

### 3. Enable CloudWatch Log Export

1. Go to RDS Console → Modify Instance
2. Under "Log exports", enable **PostgreSQL log**
3. Apply changes (may require brief downtime)

### 4. Configure RDS Security Group

Add inbound rule to allow the collector to connect:

```
Type: PostgreSQL
Port: 5432
Source: <Collector Security Group ID>
Description: PostgreSQL collector access
```

### 5. Store Credentials in Secrets Manager

```bash
# Store Last9 auth header
aws secretsmanager create-secret \
  --name postgresql-collector/prod/last9-auth \
  --secret-string '{"auth_header":"Basic YOUR_BASE64_AUTH"}'

# Store database credentials
aws secretsmanager create-secret \
  --name postgresql-collector/prod/db-credentials \
  --secret-string '{
    "username":"otel_monitor",
    "password":"YOUR_SECURE_PASSWORD",
    "host":"your-rds-endpoint.region.rds.amazonaws.com",
    "port":5432,
    "dbname":"your_database"
  }'
```

### 6. Deploy and Verify

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster postgresql-collector-prod \
  --services postgresql-collector-prod

# View collector logs
aws logs tail /ecs/postgresql-collector/prod --follow

# Verify metrics in Last9
# Navigate to Last9 dashboard and search for postgresql.* metrics
```

## Metrics Collected

### PostgreSQL Metrics (via pg_stat_*)

| Metric | Description |
|--------|-------------|
| `postgresql.connection.count` | Active connections by state |
| `postgresql.commits` | Transaction commits per database |
| `postgresql.rollbacks` | Transaction rollbacks per database |
| `postgresql.deadlocks` | Deadlock count |
| `postgresql.blocks_read` | Blocks read (cache vs disk) |
| `postgresql.rows` | Row operations (fetched, inserted, updated, deleted) |
| `postgresql.db_size` | Database size in bytes |
| `postgresql.replication.data_delay` | Replication lag in seconds |
| `postgresql.wal.lag` | WAL lag in bytes |
| `postgresql.table.vacuum.count` | Vacuum operations |

### RDS Host Metrics (via CloudWatch)

| Metric | Description |
|--------|-------------|
| `aws.rds.CPUUtilization` | CPU utilization percentage |
| `aws.rds.DatabaseConnections` | Active database connections |
| `aws.rds.FreeableMemory` | Available RAM |
| `aws.rds.FreeStorageSpace` | Available storage |
| `aws.rds.ReadIOPS` / `aws.rds.WriteIOPS` | I/O operations per second |
| `aws.rds.ReadLatency` / `aws.rds.WriteLatency` | I/O latency |
| `aws.rds.ReplicaLag` | Replication lag (read replicas) |

### Logs Collected

- **Slow queries**: Queries exceeding 100ms (configurable via `log_min_duration_statement`)
- **Errors**: PostgreSQL error and warning messages

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `PG_ENDPOINT` | RDS endpoint hostname | Yes |
| `PG_PORT` | PostgreSQL port (default: 5432) | No |
| `PG_USERNAME` | Monitoring user | Yes |
| `PG_PASSWORD` | Monitoring user password | Yes |
| `PG_DATABASE` | Database to connect to | Yes |
| `AWS_REGION` | AWS region | Yes |
| `RDS_INSTANCE_ID` | RDS instance identifier | Yes |
| `LAST9_OTLP_ENDPOINT` | Last9 OTLP endpoint | Yes |
| `LAST9_AUTH_HEADER` | Last9 authentication header | Yes |
| `ENVIRONMENT` | Environment tag (prod/staging/dev) | No |

### Collector Resource Sizing

| RDS Instances | Databases | CPU | Memory |
|---------------|-----------|-----|--------|
| 1-5 | 1-10 | 256 | 512 MB |
| 5-15 | 10-50 | 512 | 1024 MB |
| 15-30 | 50-100 | 1024 | 2048 MB |
| 30+ | 100+ | 2048 | 4096 MB |

## Troubleshooting

### Collector not starting

```bash
# Check ECS task logs
aws logs tail /ecs/postgresql-collector/prod --since 1h

# Common issues:
# - Invalid credentials in Secrets Manager
# - Security group blocking PostgreSQL port
# - RDS parameter group not configured
```

### No metrics appearing

1. Verify collector health: `curl http://localhost:13133/health`
2. Check PostgreSQL connectivity from collector
3. Verify pg_stat_statements extension is enabled
4. Check Last9 auth header is correct

### Connection refused to RDS

```bash
# Verify security group allows collector → RDS
aws ec2 describe-security-groups --group-ids sg-xxx

# Test from collector container
docker exec -it postgresql-collector sh
wget -qO- http://localhost:13133/health
```

### pg_stat_statements empty

```sql
-- Check extension is loaded
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';

-- Check parameter
SHOW shared_preload_libraries;

-- If empty, reboot RDS instance after setting shared_preload_libraries
```

## Validation (Datadog Migration)

When running in parallel with Datadog, compare these key metrics:

| Metric Type | Datadog | Last9 (OTEL) |
|-------------|---------|--------------|
| Connections | `postgresql.connections` | `postgresql.connection.count` |
| Commits | `postgresql.commits` | `postgresql.commits` |
| Cache hit ratio | `postgresql.buffer_hit` | `postgresql.blocks_read{source="cache"}` |
| Replication lag | `postgresql.replication_delay` | `postgresql.replication.data_delay` |
| RDS CPU | `aws.rds.cpuutilization` | `aws.rds.CPUUtilization` |

## Files

```
aws/rds-postgresql-ecs/
├── README.md                           # This file
├── SPEC.md                             # Detailed specification
├── docker-compose.yaml                 # Local testing
├── Dockerfile                          # Custom collector image
├── .env.example                        # Environment template
├── .gitignore                          # Git ignore rules
├── config/
│   ├── otel-collector-config.yaml      # OTEL Collector config
│   └── queries.yaml                    # Custom PostgreSQL queries
├── scripts/
│   ├── setup-db-user.sql               # Database user setup
│   └── download-rds-ca.sh              # Download RDS CA bundle
├── cloudformation/
│   └── postgresql-collector.yaml       # CloudFormation template
└── cdk/
    ├── package.json
    ├── tsconfig.json
    ├── cdk.json
    ├── bin/app.ts                      # CDK app entry
    └── lib/postgresql-collector-stack.ts
```

## Datadog DBM Feature Mapping

This integration provides feature parity with [Datadog Database Monitoring](https://docs.datadoghq.com/database_monitoring/setup_postgres/rds/):

| Datadog DBM Feature | Last9 Implementation | Status |
|---------------------|---------------------|--------|
| Query Metrics | OTEL PostgreSQL receiver + pg_stat_statements | ✅ |
| Query Samples | DBM collector polling pg_stat_activity | ✅ |
| EXPLAIN Plans | `otel_monitor.explain_statement()` function | ✅ |
| Wait Events | pg_stat_activity wait_event columns | ✅ |
| Blocking Queries | `otel_monitor.blocking_queries` view | ✅ |
| Database Load | CloudWatch RDS metrics | ✅ |
| Connection Metrics | OTEL PostgreSQL receiver | ✅ |
| Replication Lag | pg_stat_replication + CloudWatch | ✅ |
| Slow Query Logs | CloudWatch Logs receiver | ✅ |
| Query Normalization | Hash-based query signatures | ✅ |
| Database Autodiscovery | Tag-based RDS discovery | ✅ |

### Database User Comparison

The setup script (`scripts/setup-db-user.sql`) creates equivalent permissions to Datadog's setup:

```sql
-- Datadog creates:
CREATE SCHEMA datadog;
CREATE FUNCTION datadog.pg_stat_activity() ...
CREATE FUNCTION datadog.pg_stat_statements() ...

-- This integration creates:
CREATE SCHEMA otel_monitor;
CREATE FUNCTION otel_monitor.pg_stat_activity() ...
CREATE FUNCTION otel_monitor.pg_stat_statements() ...
CREATE FUNCTION otel_monitor.explain_statement() ...
CREATE VIEW otel_monitor.blocking_queries ...
CREATE VIEW otel_monitor.wait_events ...
```

## Support

- [Last9 Documentation](https://docs.last9.io)
- [Datadog DBM Reference](https://docs.datadoghq.com/database_monitoring/setup_postgres/rds/)
- [OpenTelemetry PostgreSQL Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/postgresqlreceiver)
- [AWS RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/)
