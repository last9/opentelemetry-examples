# RDS PostgreSQL Deep Integration Specification

## Datadog DBM Migration to Last9 via OpenTelemetry

**Version:** 1.0
**Status:** Draft
**Last Updated:** 2025-12-30

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Requirements Summary](#requirements-summary)
4. [RDS Configuration](#rds-configuration)
5. [Collector Design](#collector-design)
6. [Metrics Specification](#metrics-specification)
7. [Log Collection](#log-collection)
8. [Query Monitoring (DBM Parity)](#query-monitoring-dbm-parity)
9. [AWS Integration](#aws-integration)
10. [Security Model](#security-model)
11. [Deployment](#deployment)
12. [Dashboards and Alerting](#dashboards-and-alerting)
13. [Validation and Testing](#validation-and-testing)
14. [Sizing Guidelines](#sizing-guidelines)

---

## Executive Summary

This specification defines a deep PostgreSQL monitoring integration for RDS PostgreSQL instances, monitored from ECS Fargate, replacing Datadog's Database Monitoring (DBM) suite. The solution delivers:

- **Full pg_stat_* coverage** with OTEL semantic conventions
- **Query performance monitoring** with sampled EXPLAIN plans
- **Log-metric correlation** with multiple correlation keys
- **Tag-based RDS discovery** using environment tags
- **Hybrid Performance Insights integration** (PI where available, pg_stat_* fallback)
- **Host-level RDS metrics** via CloudWatch
- **APM span integration** for database spans in application traces

### Migration Context

Customer is migrating from Datadog's PostgreSQL integration with full DBM suite. This solution must provide feature parity for:

- Query samples and normalized query text
- Sampled execution plans (EXPLAIN)
- Wait event monitoring (real-time + historical)
- Blocking query detection
- Connection and resource metrics

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                 │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        VPC                                       │   │
│  │                                                                  │   │
│  │  ┌──────────────────┐      ┌──────────────────────────────────┐ │   │
│  │  │   RDS PostgreSQL │      │         ECS Fargate              │ │   │
│  │  │   (Multiple DBs) │◄────►│  ┌────────────────────────────┐  │ │   │
│  │  │                  │      │  │   PostgreSQL Collector     │  │ │   │
│  │  │  - Primary       │      │  │                            │  │ │   │
│  │  │  - Read Replicas │      │  │  ┌────────────────────┐    │  │ │   │
│  │  │                  │      │  │  │ OTEL Collector     │    │  │ │   │
│  │  └────────┬─────────┘      │  │  │ + PostgreSQL Rcvr  │    │  │ │   │
│  │           │                │  │  │ + AWS Rcvr (PI)    │    │  │ │   │
│  │           │                │  │  │ + CloudWatch Rcvr  │    │  │ │   │
│  │           ▼                │  │  └─────────┬──────────┘    │  │ │   │
│  │  ┌──────────────────┐      │  │            │               │  │ │   │
│  │  │ CloudWatch Logs  │      │  │            │ OTLP          │  │ │   │
│  │  │ (PG slow query + │──────┼──┼────────────┤               │  │ │   │
│  │  │  error logs)     │      │  │            │               │  │ │   │
│  │  └──────────────────┘      │  └────────────┼───────────────┘  │ │   │
│  │                            │               │                  │ │   │
│  │  ┌──────────────────┐      └───────────────┼──────────────────┘ │   │
│  │  │ Performance      │                      │                    │   │
│  │  │ Insights API     │──────────────────────┤                    │   │
│  │  └──────────────────┘                      │                    │   │
│  │                                            │                    │   │
│  │  ┌──────────────────┐                      │                    │   │
│  │  │ Secrets Manager  │                      │                    │   │
│  │  │ (DB credentials) │──────────────────────┤                    │   │
│  │  └──────────────────┘                      │                    │   │
│  │                                            │                    │   │
│  └────────────────────────────────────────────┼────────────────────┘   │
│                                               │                        │
└───────────────────────────────────────────────┼────────────────────────┘
                                                │
                                                ▼
                                    ┌───────────────────────┐
                                    │       Last9           │
                                    │   (OTLP Endpoint)     │
                                    │                       │
                                    │  - Metrics            │
                                    │  - Logs               │
                                    │  - Traces (DB spans)  │
                                    └───────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **OTEL Collector** | Central collection, processing, and export |
| **PostgreSQL Receiver** | Query pg_stat_* views for metrics |
| **AWS PI Receiver** | Fetch Performance Insights data for wait events |
| **CloudWatch Receiver** | Collect RDS instance-level metrics (CPU, memory, IOPS) |
| **CloudWatch Logs** | Source for PostgreSQL slow query and error logs |
| **Secrets Manager** | Secure storage for database credentials |
| **RDS Discovery** | Tag-based discovery of RDS instances |

---

## Requirements Summary

### Functional Requirements

| ID | Requirement | Priority | Source |
|----|-------------|----------|--------|
| FR-01 | Collect full pg_stat_* metrics (statements, bgwriter, replication, user tables, indexes) | P0 | Interview |
| FR-02 | Query performance monitoring with normalized query text | P0 | Interview |
| FR-03 | Sampled EXPLAIN plan collection | P0 | Interview |
| FR-04 | Wait event monitoring (real-time alerting + historical) | P0 | Interview |
| FR-05 | Log-metric correlation (query fingerprint, db+timestamp, connection/txn/PID) | P0 | Interview |
| FR-06 | Tag-based RDS discovery (environment tag) | P0 | Interview |
| FR-07 | Hybrid Performance Insights integration | P1 | Interview |
| FR-08 | Host-level RDS metrics (CPU, memory, disk I/O) | P0 | Interview |
| FR-09 | APM span integration for database queries | P1 | Interview |
| FR-10 | Replication lag monitoring (bytes and seconds) | P1 | Interview |
| FR-11 | Vacuum and autovacuum current state metrics | P1 | Interview |
| FR-12 | Custom SQL metrics capability (future) | P2 | Interview |
| FR-13 | Collector self-monitoring (health, scrape stats, errors) | P0 | Interview |

### Non-Functional Requirements

| ID | Requirement | Value |
|----|-------------|-------|
| NFR-01 | Collection interval | 30 seconds |
| NFR-02 | Metric naming convention | OTEL semantic conventions |
| NFR-03 | Query cardinality | Medium (1000-10000 unique queries) |
| NFR-04 | Slow query threshold | 100ms (log_min_duration_statement) |
| NFR-05 | High availability | Single collector with ECS auto-restart |
| NFR-06 | AWS account scope | Single account |
| NFR-07 | PostgreSQL version | 15+ only |
| NFR-08 | Export format | OTLP to Last9 |

---

## RDS Configuration

### Required Parameter Group Settings

Datadog DBM requires specific PostgreSQL parameters. For migration parity, verify these settings in your RDS parameter group:

```yaml
# RDS Parameter Group Configuration
Parameters:
  # Enable pg_stat_statements extension
  shared_preload_libraries: "pg_stat_statements"

  # pg_stat_statements settings
  pg_stat_statements.track: "all"           # Track all statements
  pg_stat_statements.max: 10000             # Maximum tracked statements
  pg_stat_statements.track_utility: "on"    # Track utility commands
  pg_stat_statements.track_planning: "on"   # Track planning time (PG 13+)

  # Timing and I/O tracking
  track_io_timing: "on"                     # Required for I/O stats
  track_activity_query_size: 4096           # Query text truncation size

  # Logging for slow queries
  log_min_duration_statement: 100           # Log queries > 100ms
  log_statement: "none"                     # Don't log all statements
  log_lock_waits: "on"                      # Log lock wait events

  # For detailed wait event tracking
  track_functions: "all"                    # Track function calls
```

### Enabling Extensions

Connect to each database and enable required extensions:

```sql
-- Enable pg_stat_statements (required)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify extension is active
SELECT * FROM pg_stat_statements LIMIT 1;
```

### CloudWatch Log Export

Enable PostgreSQL log export to CloudWatch:

1. Navigate to RDS Console → Modify Instance
2. Under "Log exports", enable:
   - PostgreSQL log
   - Upgrade log (optional)
3. Logs will appear in: `/aws/rds/instance/<instance-id>/postgresql`

---

## Collector Design

### OpenTelemetry Collector Configuration

```yaml
# otel-collector-config.yaml
receivers:
  # PostgreSQL metrics receiver
  postgresql:
    endpoint: "${env:PG_ENDPOINT}"
    transport: tcp
    username: "${env:PG_USERNAME}"
    password: "${env:PG_PASSWORD}"
    databases:
      - ${env:PG_DATABASE}
    collection_interval: 30s
    tls:
      insecure: false
      ca_file: /etc/ssl/certs/rds-ca-bundle.pem
    metrics:
      postgresql.bgwriter.buffers.allocated:
        enabled: true
      postgresql.bgwriter.buffers.writes:
        enabled: true
      postgresql.bgwriter.checkpoint.count:
        enabled: true
      postgresql.bgwriter.duration:
        enabled: true
      postgresql.blocks_read:
        enabled: true
      postgresql.commits:
        enabled: true
      postgresql.connection.count:
        enabled: true
      postgresql.database.count:
        enabled: true
      postgresql.db_size:
        enabled: true
      postgresql.deadlocks:
        enabled: true
      postgresql.index.scans:
        enabled: true
      postgresql.index.size:
        enabled: true
      postgresql.operations:
        enabled: true
      postgresql.replication.data_delay:
        enabled: true
      postgresql.rollbacks:
        enabled: true
      postgresql.rows:
        enabled: true
      postgresql.sequential_scans:
        enabled: true
      postgresql.table.count:
        enabled: true
      postgresql.table.size:
        enabled: true
      postgresql.table.vacuum.count:
        enabled: true
      postgresql.temp_files:
        enabled: true
      postgresql.wal.age:
        enabled: true
      postgresql.wal.lag:
        enabled: true

  # AWS CloudWatch receiver for RDS host metrics
  awscloudwatch:
    region: ${env:AWS_REGION}
    poll_interval: 30s
    metrics:
      named:
        # RDS Instance Metrics
        - namespace: AWS/RDS
          metric_name: CPUUtilization
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: DatabaseConnections
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: FreeableMemory
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: FreeStorageSpace
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: ReadIOPS
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: WriteIOPS
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: ReadLatency
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: WriteLatency
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]
        - namespace: AWS/RDS
          metric_name: ReplicaLag
          dimensions:
            - name: DBInstanceIdentifier
              value: ${env:RDS_INSTANCE_ID}
          period: 1m
          statistics: [Average]

  # AWS CloudWatch Logs receiver for PostgreSQL logs
  awscloudwatchlogs:
    region: ${env:AWS_REGION}
    logs:
      poll_interval: 10s
      groups:
        named:
          /aws/rds/instance/${env:RDS_INSTANCE_ID}/postgresql:
            receivers:
              log_group:
                auto_discover:
                  limit: 100

  # Prometheus receiver for self-monitoring
  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          static_configs:
            - targets: ['localhost:8888']

processors:
  # Batch processing for efficiency
  batch:
    timeout: 10s
    send_batch_size: 1000

  # Add resource attributes
  resource:
    attributes:
      - key: service.name
        value: postgresql-collector
        action: upsert
      - key: deployment.environment
        value: ${env:ENVIRONMENT}
        action: upsert
      - key: db.system
        value: postgresql
        action: upsert
      - key: cloud.provider
        value: aws
        action: upsert
      - key: cloud.platform
        value: aws_rds
        action: upsert

  # Memory limiter for stability
  memory_limiter:
    check_interval: 5s
    limit_mib: 400
    spike_limit_mib: 100

  # Attributes processing for log correlation
  attributes:
    actions:
      - key: db.instance.id
        value: ${env:RDS_INSTANCE_ID}
        action: upsert

exporters:
  # Last9 OTLP exporter
  otlp:
    endpoint: ${env:LAST9_OTLP_ENDPOINT}
    headers:
      Authorization: ${env:LAST9_AUTH_HEADER}
    tls:
      insecure: false

  # Debug exporter for troubleshooting
  debug:
    verbosity: basic

extensions:
  # Health check for ECS
  health_check:
    endpoint: 0.0.0.0:13133
    path: /health

  # Metrics endpoint for self-monitoring
  zpages:
    endpoint: 0.0.0.0:55679

service:
  extensions: [health_check, zpages]
  pipelines:
    metrics:
      receivers: [postgresql, awscloudwatch, prometheus]
      processors: [memory_limiter, batch, resource, attributes]
      exporters: [otlp]
    logs:
      receivers: [awscloudwatchlogs]
      processors: [memory_limiter, batch, resource, attributes]
      exporters: [otlp]

  telemetry:
    logs:
      level: info
    metrics:
      level: detailed
      address: 0.0.0.0:8888
```

---

## Metrics Specification

### OTEL Semantic Convention Mapping

Using [OpenTelemetry Database Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/database/):

| Metric Name | Type | Unit | Description | Datadog Equivalent |
|-------------|------|------|-------------|-------------------|
| `db.client.connections.usage` | Gauge | `{connection}` | Active connections | `postgresql.connections` |
| `db.client.connections.max` | Gauge | `{connection}` | Max connections | `postgresql.max_connections` |
| `postgresql.commits` | Counter | `{transaction}` | Commits per database | `postgresql.commits` |
| `postgresql.rollbacks` | Counter | `{transaction}` | Rollbacks per database | `postgresql.rollbacks` |
| `postgresql.deadlocks` | Counter | `{deadlock}` | Deadlock count | `postgresql.deadlocks` |
| `postgresql.blocks_read` | Counter | `{block}` | Blocks read (heap/idx/toast/tidx) | `postgresql.buffer_hit` |
| `postgresql.rows` | Counter | `{row}` | Rows fetched/returned/inserted/updated/deleted | `postgresql.rows_*` |
| `postgresql.operations` | Counter | `{operation}` | Operations (hot_update, idx_scan, seq_scan) | `postgresql.index_rows_*` |
| `postgresql.db_size` | Gauge | `By` | Database size in bytes | `postgresql.database_size` |
| `postgresql.table.size` | Gauge | `By` | Table size | `postgresql.table_size` |
| `postgresql.index.size` | Gauge | `By` | Index size | `postgresql.index_size` |
| `postgresql.wal.lag` | Gauge | `By` | WAL lag in bytes (replication) | `postgresql.replication_delay_bytes` |
| `postgresql.replication.data_delay` | Gauge | `s` | Replication delay in seconds | `postgresql.replication_delay` |
| `postgresql.bgwriter.*` | Counter/Gauge | various | Background writer stats | `postgresql.bgwriter.*` |
| `postgresql.temp_files` | Counter | `{file}` | Temp files created | `postgresql.temp_files` |
| `postgresql.table.vacuum.count` | Counter | `{vacuum}` | Vacuum operations | `postgresql.vacuum_count` |

### pg_stat_statements Metrics

For query-level metrics from `pg_stat_statements`:

| Metric Name | Type | Unit | Description |
|-------------|------|------|-------------|
| `db.client.operation.duration` | Histogram | `ms` | Query execution time |
| `postgresql.statements.calls` | Counter | `{call}` | Number of query executions |
| `postgresql.statements.rows` | Counter | `{row}` | Total rows returned |
| `postgresql.statements.shared_blks_hit` | Counter | `{block}` | Shared buffer hits |
| `postgresql.statements.shared_blks_read` | Counter | `{block}` | Shared blocks read from disk |
| `postgresql.statements.blk_read_time` | Counter | `ms` | Block read time |
| `postgresql.statements.blk_write_time` | Counter | `ms` | Block write time |

### Resource Attributes

All metrics include:

```yaml
resource.attributes:
  service.name: postgresql-collector
  db.system: postgresql
  db.name: <database_name>
  db.instance.id: <rds_instance_id>
  cloud.provider: aws
  cloud.platform: aws_rds
  cloud.region: <aws_region>
  deployment.environment: <prod|staging|dev>
```

### Metric Labels/Attributes

| Label | Description | Applied To |
|-------|-------------|------------|
| `db.name` | Database name | All metrics |
| `db.operation` | Query operation type | Query metrics |
| `db.statement` | Normalized query (with placeholders) | Query metrics |
| `db.query.id` | Query fingerprint/hash | Query metrics |
| `state` | Connection state (active, idle, etc.) | Connection metrics |
| `wait_event_type` | PostgreSQL wait event type | Wait event metrics |
| `wait_event` | Specific wait event | Wait event metrics |

---

## Log Collection

### Log Types Collected

| Log Type | Source | Purpose |
|----------|--------|---------|
| Slow query log | CloudWatch Logs | Queries exceeding 100ms threshold |
| Error log | CloudWatch Logs | PostgreSQL errors and warnings |

### Log Format and Parsing

PostgreSQL logs in CloudWatch follow this pattern:

```
2025-12-30 10:15:30 UTC:192.168.1.100(12345):postgres@mydb:[5678]:LOG:  duration: 150.234 ms  statement: SELECT * FROM users WHERE id = $1
```

### Log Attributes for Correlation

Extract and index the following attributes:

| Attribute | Extraction Pattern | Correlation Use |
|-----------|-------------------|-----------------|
| `timestamp` | ISO 8601 timestamp | Time-based correlation |
| `db.name` | `@mydb` from log line | Database correlation |
| `db.user` | `postgres` from log line | User correlation |
| `db.client.address` | IP from connection info | Connection tracking |
| `db.connection.id` | PID from `[5678]` | Connection ID correlation |
| `log.level` | LOG/ERROR/WARNING | Severity filtering |
| `db.query.duration_ms` | `duration: X ms` | Performance correlation |
| `db.statement` | Statement text | Query fingerprint matching |

### Log-Metric Correlation Keys

Support correlation via:

1. **Query fingerprint**: Hash normalized query text, match between logs and `pg_stat_statements`
2. **Database + timestamp**: Join by `db.name` within time window
3. **Connection context**: `db.connection.id` (PID), transaction ID, backend PID

---

## Query Monitoring (DBM Parity)

### Query Samples Collection

Collect query samples from `pg_stat_activity` at 30-second intervals:

```sql
-- Query samples collection
SELECT
    pid,
    datname AS database,
    usename AS username,
    application_name,
    client_addr,
    client_port,
    backend_start,
    xact_start,
    query_start,
    state_change,
    wait_event_type,
    wait_event,
    state,
    backend_xid,
    backend_xmin,
    left(query, 4096) AS query,
    query_id
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
  AND query NOT LIKE '%pg_stat_activity%';
```

### Normalized Query Text

Query normalization rules (matching Datadog behavior):

1. Replace literal values with placeholders (`$1`, `$2`, etc.)
2. Normalize whitespace (collapse multiple spaces)
3. Remove comments
4. Generate consistent fingerprint/hash

Example:
```sql
-- Original
SELECT * FROM users WHERE id = 123 AND email = 'test@example.com'

-- Normalized
SELECT * FROM users WHERE id = $1 AND email = $2
```

### EXPLAIN Plan Sampling

Collect EXPLAIN plans for slow queries using sampling:

```yaml
explain_sampling:
  # Sample rate (1 in N qualifying queries gets EXPLAIN)
  sample_rate: 100

  # Only explain queries exceeding this threshold
  duration_threshold_ms: 100

  # EXPLAIN options
  explain_options:
    - ANALYZE: false      # Don't actually execute
    - COSTS: true
    - FORMAT: JSON
    - BUFFERS: false      # Skip buffer info for performance

  # Rate limiting
  max_explains_per_minute: 10
```

### Wait Event Monitoring

#### Real-time Blocking Detection

Poll `pg_stat_activity` for blocking queries:

```sql
-- Blocking queries detection
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query,
    now() - blocked_activity.query_start AS blocked_duration
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

#### Wait Event Aggregation

Aggregate wait events from `pg_stat_activity`:

```sql
-- Wait event aggregation
SELECT
    wait_event_type,
    wait_event,
    count(*) AS count,
    datname AS database
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
  AND state = 'active'
GROUP BY wait_event_type, wait_event, datname;
```

### Statistics Handling

- **Never reset `pg_stat_statements`** - collector tracks cumulative values
- **Derive rates** from delta between consecutive scrapes
- **Handle counter resets** gracefully (detect via `stats_reset` column)

---

## AWS Integration

### Performance Insights Integration

When Performance Insights is enabled, fetch enhanced wait event data:

```python
# PI API call example
response = pi_client.get_resource_metrics(
    ServiceType='RDS',
    Identifier=f'db-{rds_instance_id}',
    MetricQueries=[
        {
            'Metric': 'db.load.avg',
            'GroupBy': {
                'Group': 'db.wait_event',
                'Limit': 10
            }
        },
        {
            'Metric': 'db.sql.stats.calls_per_sec.avg',
            'GroupBy': {
                'Group': 'db.sql',
                'Limit': 25
            }
        }
    ],
    StartTime=start_time,
    EndTime=end_time,
    PeriodInSeconds=60
)
```

### Fallback Strategy

```yaml
# Hybrid PI/pg_stat_* configuration
performance_insights:
  enabled: true
  fallback_to_pg_stat: true

  # Use PI for these when available
  prefer_pi_for:
    - wait_events
    - top_sql
    - db_load

  # Always use pg_stat_* for these
  always_pg_stat:
    - pg_stat_statements  # More detailed
    - pg_stat_replication # PI doesn't cover
    - pg_stat_bgwriter    # PI doesn't cover
```

### RDS Tag-Based Discovery

Discover RDS instances by environment tag:

```python
# Discovery logic
def discover_rds_instances(environment: str) -> list[RDSInstance]:
    """
    Discover RDS PostgreSQL instances matching environment tag.
    """
    rds = boto3.client('rds')

    instances = []
    paginator = rds.get_paginator('describe_db_instances')

    for page in paginator.paginate(
        Filters=[
            {'Name': 'engine', 'Values': ['postgres']},
        ]
    ):
        for db in page['DBInstances']:
            # Check tags
            tags = {t['Key']: t['Value']
                   for t in rds.list_tags_for_resource(
                       ResourceName=db['DBInstanceArn']
                   )['TagList']}

            if tags.get('Environment') == environment:
                instances.append(RDSInstance(
                    identifier=db['DBInstanceIdentifier'],
                    endpoint=db['Endpoint']['Address'],
                    port=db['Endpoint']['Port'],
                    engine_version=db['EngineVersion'],
                    has_performance_insights=db.get('PerformanceInsightsEnabled', False),
                    has_read_replica=bool(db.get('ReadReplicaDBInstanceIdentifiers')),
                ))

    return instances
```

---

## Security Model

### IAM Role Permissions

ECS Task IAM Role policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSDiscovery",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PerformanceInsights",
      "Effect": "Allow",
      "Action": [
        "pi:GetResourceMetrics",
        "pi:GetDimensionKeyDetails",
        "pi:DescribeDimensionKeys"
      ],
      "Resource": "arn:aws:pi:*:*:metrics/rds/*"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/rds/*"
    },
    {
      "Sid": "SecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:rds/postgresql/*"
    }
  ]
}
```

### Database User Setup

Create dedicated monitoring user with minimal permissions:

```sql
-- Create monitoring user
CREATE USER otel_monitor WITH PASSWORD '<secure_password_from_secrets_manager>';

-- Grant pg_monitor role (PostgreSQL 10+)
GRANT pg_monitor TO otel_monitor;

-- Required for pg_stat_statements
GRANT EXECUTE ON FUNCTION pg_stat_statements_reset() TO otel_monitor;

-- Connect permission to databases
GRANT CONNECT ON DATABASE <database_name> TO otel_monitor;

-- For each database to monitor
\c <database_name>
GRANT USAGE ON SCHEMA public TO otel_monitor;
GRANT SELECT ON pg_stat_statements TO otel_monitor;
```

### Secrets Manager Structure

Store credentials in Secrets Manager:

```json
{
  "secretName": "rds/postgresql/otel-monitor",
  "secretValue": {
    "username": "otel_monitor",
    "password": "<generated_secure_password>",
    "engine": "postgres",
    "host": "<rds_endpoint>",
    "port": 5432,
    "dbname": "<database_name>"
  }
}
```

### Security Review Checklist

Items requiring security team review:

- [ ] VPC-only access (collector runs in private subnet)
- [ ] TLS encryption for database connections (RDS CA bundle)
- [ ] TLS encryption for OTLP export to Last9
- [ ] Secrets Manager rotation policy
- [ ] IAM role least-privilege verification
- [ ] Network security group rules
- [ ] Audit logging of collector activity

---

## Deployment

### CDK Stack

```typescript
// lib/postgresql-collector-stack.ts
import * as cdk from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface PostgreSQLCollectorStackProps extends cdk.StackProps {
  vpcId: string;
  environment: string;
  last9OtlpEndpoint: string;
}

export class PostgreSQLCollectorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: PostgreSQLCollectorStackProps) {
    super(scope, id, props);

    // Import existing VPC
    const vpc = ec2.Vpc.fromLookup(this, 'VPC', {
      vpcId: props.vpcId,
    });

    // Create ECS Cluster
    const cluster = new ecs.Cluster(this, 'CollectorCluster', {
      vpc,
      clusterName: `postgresql-collector-${props.environment}`,
    });

    // Create secrets for Last9 auth
    const last9AuthSecret = new secretsmanager.Secret(this, 'Last9AuthSecret', {
      secretName: `postgresql-collector/${props.environment}/last9-auth`,
      description: 'Last9 OTLP authentication header',
    });

    // Reference existing database credentials secret
    const dbCredentialsSecret = secretsmanager.Secret.fromSecretNameV2(
      this,
      'DBCredentials',
      'rds/postgresql/otel-monitor'
    );

    // Task execution role
    const executionRole = new iam.Role(this, 'ExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          'service-role/AmazonECSTaskExecutionRolePolicy'
        ),
      ],
    });

    // Grant secret access to execution role
    last9AuthSecret.grantRead(executionRole);
    dbCredentialsSecret.grantRead(executionRole);

    // Task role with AWS API permissions
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    // Add IAM policy for RDS discovery, PI, CloudWatch
    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        'rds:DescribeDBInstances',
        'rds:ListTagsForResource',
      ],
      resources: ['*'],
    }));

    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        'pi:GetResourceMetrics',
        'pi:GetDimensionKeyDetails',
        'pi:DescribeDimensionKeys',
      ],
      resources: ['arn:aws:pi:*:*:metrics/rds/*'],
    }));

    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:GetMetricData',
        'cloudwatch:ListMetrics',
      ],
      resources: ['*'],
    }));

    taskRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        'logs:GetLogEvents',
        'logs:FilterLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
      ],
      resources: ['arn:aws:logs:*:*:log-group:/aws/rds/*'],
    }));

    // Task definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole,
      taskRole,
    });

    // CloudWatch log group for collector logs
    const logGroup = new logs.LogGroup(this, 'CollectorLogs', {
      logGroupName: `/ecs/postgresql-collector/${props.environment}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Container definition
    const container = taskDefinition.addContainer('otel-collector', {
      image: ecs.ContainerImage.fromRegistry(
        'otel/opentelemetry-collector-contrib:latest'
      ),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'collector',
        logGroup,
      }),
      environment: {
        ENVIRONMENT: props.environment,
        AWS_REGION: this.region,
        LAST9_OTLP_ENDPOINT: props.last9OtlpEndpoint,
      },
      secrets: {
        LAST9_AUTH_HEADER: ecs.Secret.fromSecretsManager(last9AuthSecret),
        PG_USERNAME: ecs.Secret.fromSecretsManager(dbCredentialsSecret, 'username'),
        PG_PASSWORD: ecs.Secret.fromSecretsManager(dbCredentialsSecret, 'password'),
        PG_ENDPOINT: ecs.Secret.fromSecretsManager(dbCredentialsSecret, 'host'),
        PG_DATABASE: ecs.Secret.fromSecretsManager(dbCredentialsSecret, 'dbname'),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'wget --spider -q http://localhost:13133/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    container.addPortMappings(
      { containerPort: 13133, protocol: ecs.Protocol.TCP }, // Health check
      { containerPort: 8888, protocol: ecs.Protocol.TCP },  // Metrics
    );

    // Security group
    const securityGroup = new ec2.SecurityGroup(this, 'CollectorSG', {
      vpc,
      description: 'Security group for PostgreSQL collector',
      allowAllOutbound: true,
    });

    // Allow inbound for health checks (if using ALB)
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(13133),
      'Health check from VPC'
    );

    // Fargate service
    const service = new ecs.FargateService(this, 'CollectorService', {
      cluster,
      taskDefinition,
      desiredCount: 1,
      assignPublicIp: false,
      securityGroups: [securityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      circuitBreaker: {
        rollback: true,
      },
      enableECSManagedTags: true,
      propagateTags: ecs.PropagatedTagSource.SERVICE,
    });

    // Outputs
    new cdk.CfnOutput(this, 'ClusterArn', {
      value: cluster.clusterArn,
    });

    new cdk.CfnOutput(this, 'ServiceArn', {
      value: service.serviceArn,
    });
  }
}
```

### CloudFormation Template

```yaml
# cloudformation/postgresql-collector.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: PostgreSQL Collector for Last9 Integration

Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC to deploy the collector

  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>
    Description: Private subnets for Fargate tasks

  Environment:
    Type: String
    AllowedValues: [prod, staging, dev]
    Description: Deployment environment

  Last9OtlpEndpoint:
    Type: String
    Description: Last9 OTLP endpoint URL

  DBCredentialsSecretArn:
    Type: String
    Description: ARN of Secrets Manager secret containing DB credentials

Resources:
  ECSCluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: !Sub 'postgresql-collector-${Environment}'
      CapacityProviders:
        - FARGATE
      DefaultCapacityProviderStrategy:
        - CapacityProvider: FARGATE
          Weight: 1

  ExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ecs-tasks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
      Policies:
        - PolicyName: SecretsAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - secretsmanager:GetSecretValue
                Resource:
                  - !Ref DBCredentialsSecretArn
                  - !Ref Last9AuthSecret

  TaskRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ecs-tasks.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: AWSAccessPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Sid: RDSDiscovery
                Effect: Allow
                Action:
                  - rds:DescribeDBInstances
                  - rds:ListTagsForResource
                Resource: '*'
              - Sid: PerformanceInsights
                Effect: Allow
                Action:
                  - pi:GetResourceMetrics
                  - pi:GetDimensionKeyDetails
                  - pi:DescribeDimensionKeys
                Resource: 'arn:aws:pi:*:*:metrics/rds/*'
              - Sid: CloudWatchMetrics
                Effect: Allow
                Action:
                  - cloudwatch:GetMetricStatistics
                  - cloudwatch:GetMetricData
                  - cloudwatch:ListMetrics
                Resource: '*'
              - Sid: CloudWatchLogs
                Effect: Allow
                Action:
                  - logs:GetLogEvents
                  - logs:FilterLogEvents
                  - logs:DescribeLogGroups
                  - logs:DescribeLogStreams
                Resource: 'arn:aws:logs:*:*:log-group:/aws/rds/*'

  Last9AuthSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub 'postgresql-collector/${Environment}/last9-auth'
      Description: Last9 OTLP authentication header

  LogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/ecs/postgresql-collector/${Environment}'
      RetentionInDays: 14

  TaskDefinition:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: postgresql-collector
      Cpu: '256'
      Memory: '512'
      NetworkMode: awsvpc
      RequiresCompatibilities:
        - FARGATE
      ExecutionRoleArn: !GetAtt ExecutionRole.Arn
      TaskRoleArn: !GetAtt TaskRole.Arn
      ContainerDefinitions:
        - Name: otel-collector
          Image: otel/opentelemetry-collector-contrib:latest
          Essential: true
          PortMappings:
            - ContainerPort: 13133
              Protocol: tcp
            - ContainerPort: 8888
              Protocol: tcp
          Environment:
            - Name: ENVIRONMENT
              Value: !Ref Environment
            - Name: AWS_REGION
              Value: !Ref AWS::Region
            - Name: LAST9_OTLP_ENDPOINT
              Value: !Ref Last9OtlpEndpoint
          Secrets:
            - Name: LAST9_AUTH_HEADER
              ValueFrom: !Ref Last9AuthSecret
            - Name: PG_USERNAME
              ValueFrom: !Sub '${DBCredentialsSecretArn}:username::'
            - Name: PG_PASSWORD
              ValueFrom: !Sub '${DBCredentialsSecretArn}:password::'
            - Name: PG_ENDPOINT
              ValueFrom: !Sub '${DBCredentialsSecretArn}:host::'
            - Name: PG_DATABASE
              ValueFrom: !Sub '${DBCredentialsSecretArn}:dbname::'
          LogConfiguration:
            LogDriver: awslogs
            Options:
              awslogs-group: !Ref LogGroup
              awslogs-region: !Ref AWS::Region
              awslogs-stream-prefix: collector
          HealthCheck:
            Command:
              - CMD-SHELL
              - 'wget --spider -q http://localhost:13133/health || exit 1'
            Interval: 30
            Timeout: 5
            Retries: 3
            StartPeriod: 60

  SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for PostgreSQL collector
      VpcId: !Ref VpcId
      SecurityGroupEgress:
        - IpProtocol: '-1'
          CidrIp: 0.0.0.0/0

  Service:
    Type: AWS::ECS::Service
    Properties:
      ServiceName: postgresql-collector
      Cluster: !Ref ECSCluster
      TaskDefinition: !Ref TaskDefinition
      DesiredCount: 1
      LaunchType: FARGATE
      NetworkConfiguration:
        AwsvpcConfiguration:
          AssignPublicIp: DISABLED
          SecurityGroups:
            - !Ref SecurityGroup
          Subnets: !Ref SubnetIds
      DeploymentConfiguration:
        MaximumPercent: 200
        MinimumHealthyPercent: 100
        DeploymentCircuitBreaker:
          Enable: true
          Rollback: true

Outputs:
  ClusterArn:
    Value: !GetAtt ECSCluster.Arn
    Export:
      Name: !Sub '${AWS::StackName}-ClusterArn'

  ServiceArn:
    Value: !Ref Service
    Export:
      Name: !Sub '${AWS::StackName}-ServiceArn'
```

---

## Dashboards and Alerting

### Dashboard Panels

#### Overview Dashboard

| Panel | Metrics | Visualization |
|-------|---------|---------------|
| Active Connections | `db.client.connections.usage` | Gauge |
| Connections % | `db.client.connections.usage / db.client.connections.max * 100` | Gauge with thresholds |
| Transactions/sec | `rate(postgresql.commits) + rate(postgresql.rollbacks)` | Time series |
| Cache Hit Ratio | `postgresql.blocks_read{source="cache"} / sum(postgresql.blocks_read)` | Gauge |
| Deadlocks | `rate(postgresql.deadlocks)` | Time series |
| Database Size | `postgresql.db_size` | Bar chart by database |

#### Query Performance Dashboard

| Panel | Metrics | Visualization |
|-------|---------|---------------|
| Top Queries by Time | `topk(10, postgresql.statements.total_time)` | Table |
| Slowest Queries | `topk(10, postgresql.statements.mean_time)` | Table with query text |
| Queries/sec | `rate(postgresql.statements.calls)` | Time series |
| Row Operations | `rate(postgresql.rows)` by operation | Stacked area |
| Buffer Hit Ratio by Query | `postgresql.statements.shared_blks_hit / (shared_blks_hit + shared_blks_read)` | Table |

#### Wait Events Dashboard

| Panel | Metrics | Visualization |
|-------|---------|---------------|
| Wait Events by Type | `postgresql.wait_events` grouped by `wait_event_type` | Pie chart |
| Top Wait Events | `topk(10, postgresql.wait_events)` | Table |
| Lock Waits | `postgresql.wait_events{wait_event_type="Lock"}` | Time series |
| Active Blocking Queries | `postgresql.blocking_queries` | Table with query details |

#### Replication Dashboard

| Panel | Metrics | Visualization |
|-------|---------|---------------|
| Replication Lag (bytes) | `postgresql.wal.lag` | Time series by replica |
| Replication Lag (seconds) | `postgresql.replication.data_delay` | Time series by replica |
| WAL Position | `postgresql.wal.position` | Time series (primary vs replica) |

#### Host Metrics Dashboard (RDS)

| Panel | Metrics | Visualization |
|-------|---------|---------------|
| CPU Utilization | `aws.rds.CPUUtilization` | Time series |
| Freeable Memory | `aws.rds.FreeableMemory` | Time series |
| Free Storage Space | `aws.rds.FreeStorageSpace` | Time series with threshold |
| Read/Write IOPS | `aws.rds.ReadIOPS`, `aws.rds.WriteIOPS` | Stacked area |
| Read/Write Latency | `aws.rds.ReadLatency`, `aws.rds.WriteLatency` | Time series |

### Alerting Rules

#### Critical Alerts

```yaml
alerts:
  - name: PostgreSQLHighConnections
    condition: >
      db.client.connections.usage / db.client.connections.max > 0.9
    for: 5m
    severity: critical
    summary: "PostgreSQL connections above 90% of max"

  - name: PostgreSQLReplicationLagCritical
    condition: >
      postgresql.replication.data_delay > 60
    for: 2m
    severity: critical
    summary: "PostgreSQL replication lag exceeds 60 seconds"

  - name: PostgreSQLDeadlocks
    condition: >
      rate(postgresql.deadlocks[5m]) > 0
    for: 1m
    severity: critical
    summary: "PostgreSQL deadlocks detected"

  - name: PostgreSQLBlockingQueries
    condition: >
      postgresql.blocking_queries > 0
    for: 5m
    severity: critical
    summary: "Long-running blocking queries detected"
```

#### Warning Alerts

```yaml
alerts:
  - name: PostgreSQLHighConnections
    condition: >
      db.client.connections.usage / db.client.connections.max > 0.75
    for: 10m
    severity: warning
    summary: "PostgreSQL connections above 75% of max"

  - name: PostgreSQLReplicationLagWarning
    condition: >
      postgresql.replication.data_delay > 10
    for: 5m
    severity: warning
    summary: "PostgreSQL replication lag exceeds 10 seconds"

  - name: PostgreSQLSlowQueries
    condition: >
      rate(postgresql.slow_query_count[5m]) > 10
    for: 10m
    severity: warning
    summary: "High rate of slow queries"

  - name: PostgreSQLCacheHitRatioLow
    condition: >
      postgresql.cache_hit_ratio < 0.95
    for: 15m
    severity: warning
    summary: "PostgreSQL cache hit ratio below 95%"

  - name: RDSStorageSpaceLow
    condition: >
      aws.rds.FreeStorageSpace < 10737418240  # 10GB
    for: 30m
    severity: warning
    summary: "RDS free storage space below 10GB"
```

### Collector Health Alerts

```yaml
alerts:
  - name: CollectorDown
    condition: >
      up{job="postgresql-collector"} == 0
    for: 2m
    severity: critical
    summary: "PostgreSQL collector is down"

  - name: CollectorScrapeErrors
    condition: >
      rate(otelcol_receiver_refused_metric_points[5m]) > 0
    for: 5m
    severity: warning
    summary: "PostgreSQL collector experiencing scrape errors"

  - name: CollectorHighMemory
    condition: >
      otelcol_process_memory_rss > 400000000  # 400MB
    for: 10m
    severity: warning
    summary: "PostgreSQL collector memory usage high"
```

---

## Validation and Testing

### Spot-Check Validation Queries

Use these queries to validate metrics match between Datadog and Last9 during parallel running:

#### Connection Metrics

```sql
-- From PostgreSQL directly
SELECT
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

Compare with:
- Datadog: `postgresql.connections` with `state` tag
- Last9: `db.client.connections.usage` with `state` attribute

#### Query Metrics

```sql
-- From pg_stat_statements
SELECT
    queryid,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Compare with:
- Datadog: DBM query view, `postgresql.queries.count`
- Last9: `postgresql.statements.calls`, `db.client.operation.duration`

#### Replication Lag

```sql
-- From pg_stat_replication (on primary)
SELECT
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

Compare with:
- Datadog: `postgresql.replication_delay`, `postgresql.replication_delay_bytes`
- Last9: `postgresql.replication.data_delay`, `postgresql.wal.lag`

### Validation Checklist

| Check | How to Validate | Pass Criteria |
|-------|----------------|---------------|
| Connection count | Compare active connections | Within 5% |
| Query count | Compare top 10 queries by calls | Same ranking |
| Cache hit ratio | Compare buffer hit % | Within 1% |
| Replication lag | Compare lag values | Exact match (within precision) |
| Wait events | Compare top wait events | Same events in top 5 |
| Error logs | Compare error count | Same count |
| Host CPU | Compare RDS CPU % | Within 2% |

---

## Sizing Guidelines

### Collector Resource Recommendations

Based on number of monitored RDS instances and databases:

| RDS Instances | Databases (total) | Fargate CPU | Fargate Memory | Notes |
|---------------|-------------------|-------------|----------------|-------|
| 1-5 | 1-10 | 256 | 512 MB | Baseline |
| 5-15 | 10-50 | 512 | 1024 MB | Medium |
| 15-30 | 50-100 | 1024 | 2048 MB | Large |
| 30+ | 100+ | 2048 | 4096 MB | Consider multiple collectors |

### Cost Estimation

| Component | Cost Factor | Estimate (per month) |
|-----------|-------------|---------------------|
| Fargate (256 CPU, 512MB) | On-demand | ~$10-15 |
| CloudWatch Logs ingestion | $0.50/GB | Varies by log volume |
| Secrets Manager | $0.40/secret + API calls | ~$2-5 |
| Performance Insights API | $0.01 per 1000 requests | ~$5-20 |
| **Total baseline** | | **~$20-50/month** |

### Performance Considerations

1. **Collection interval**: 30s provides good balance; 10s doubles API calls
2. **pg_stat_statements entries**: 10,000 max; higher increases memory usage
3. **Query text truncation**: 4096 chars balances detail vs memory
4. **EXPLAIN sampling**: 1/100 sampling with 10/min cap prevents overhead

---

## Appendix

### Datadog DBM Feature Mapping

| Datadog Feature | Implementation Status | Notes |
|-----------------|----------------------|-------|
| Query Metrics | ✅ Covered | Via pg_stat_statements |
| Query Samples | ✅ Covered | Via pg_stat_activity polling |
| EXPLAIN Plans | ✅ Covered | Sampled approach |
| Wait Events | ✅ Covered | pg_stat_activity + PI |
| Blocking Queries | ✅ Covered | pg_locks join |
| Connection Metrics | ✅ Covered | Standard receiver |
| Replication Metrics | ✅ Covered | pg_stat_replication |
| Table/Index Stats | ⚠️ DB-level | Table-level not required |
| Custom Queries | 🔜 Future | Capability designed in |
| Live Query View | ⚠️ Different | Polling vs streaming |

### References

- [OpenTelemetry Database Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/database/)
- [OpenTelemetry Collector PostgreSQL Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/postgresqlreceiver)
- [Datadog PostgreSQL Integration](https://docs.datadoghq.com/integrations/postgres/)
- [Datadog Database Monitoring](https://docs.datadoghq.com/database_monitoring/)
- [AWS RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [PostgreSQL Statistics Collector](https://www.postgresql.org/docs/current/monitoring-stats.html)
