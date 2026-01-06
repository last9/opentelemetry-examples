#!/usr/bin/env python3
"""
PostgreSQL DBM Collector for Last9
Collects Database Monitoring data similar to Datadog DBM and exports via OTLP.

This script provides feature parity with Datadog's Database Monitoring:
- Query samples from pg_stat_activity
- Query metrics from pg_stat_statements
- Explain plans (sampled)
- Wait events
- Blocking queries

Reference: https://docs.datadoghq.com/database_monitoring/setup_postgres/rds/
"""

import os
import sys
import json
import time
import hashlib
import logging
import re
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, asdict
import psycopg2
from psycopg2.extras import RealDictCursor

# OpenTelemetry imports
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('dbm-collector')

# =============================================================================
# Configuration
# =============================================================================

@dataclass
class Config:
    """Collector configuration from environment variables."""
    pg_host: str = os.getenv('PG_ENDPOINT', 'localhost')
    pg_port: int = int(os.getenv('PG_PORT', '5432'))
    pg_user: str = os.getenv('PG_USERNAME', 'otel_monitor')
    pg_password: str = os.getenv('PG_PASSWORD', '')
    pg_database: str = os.getenv('PG_DATABASE', 'postgres')

    # Collection settings
    collection_interval: int = int(os.getenv('COLLECTION_INTERVAL', '30'))
    slow_query_threshold_ms: int = int(os.getenv('SLOW_QUERY_THRESHOLD_MS', '100'))
    explain_sample_rate: int = int(os.getenv('EXPLAIN_SAMPLE_RATE', '100'))  # 1 in N
    max_explains_per_interval: int = int(os.getenv('MAX_EXPLAINS_PER_INTERVAL', '10'))

    # Output settings
    output_format: str = os.getenv('OUTPUT_FORMAT', 'json')  # json, otlp
    otlp_endpoint: str = os.getenv('LAST9_OTLP_ENDPOINT', '')
    otlp_auth: str = os.getenv('LAST9_AUTH_HEADER', '')

    # Metadata
    environment: str = os.getenv('ENVIRONMENT', 'unknown')
    rds_instance_id: str = os.getenv('RDS_INSTANCE_ID', 'unknown')
    aws_region: str = os.getenv('AWS_REGION', 'unknown')


# =============================================================================
# Data Models
# =============================================================================

@dataclass
class QuerySample:
    """A sample of a running query."""
    timestamp: str
    database: str
    username: str
    pid: int
    query: str
    query_signature: str  # Normalized query hash
    duration_ms: float
    state: str
    wait_event_type: Optional[str]
    wait_event: Optional[str]
    client_addr: Optional[str]
    application_name: Optional[str]


@dataclass
class QueryMetric:
    """Aggregated metrics for a query from pg_stat_statements."""
    timestamp: str
    database: str
    username: str
    query_id: int
    query: str
    query_signature: str
    calls: int
    total_time_ms: float
    mean_time_ms: float
    rows: int
    shared_blks_hit: int
    shared_blks_read: int
    blk_read_time_ms: float
    blk_write_time_ms: float


@dataclass
class ExplainPlan:
    """EXPLAIN plan for a query."""
    timestamp: str
    database: str
    query: str
    query_signature: str
    plan: Dict[str, Any]


@dataclass
class WaitEvent:
    """Wait event aggregation."""
    timestamp: str
    database: str
    wait_event_type: str
    wait_event: str
    count: int


@dataclass
class BlockingQuery:
    """Blocking query information."""
    timestamp: str
    database: str
    blocked_pid: int
    blocked_user: str
    blocked_query: str
    blocking_pid: int
    blocking_user: str
    blocking_query: str
    blocked_duration_seconds: float
    lock_type: str


# =============================================================================
# Query Normalization
# =============================================================================

def normalize_query(query: str) -> str:
    """
    Normalize a query by replacing literals with placeholders.
    This matches Datadog's query normalization behavior.
    """
    if not query:
        return ''

    # Remove comments
    query = re.sub(r'/\*.*?\*/', '', query, flags=re.DOTALL)
    query = re.sub(r'--.*$', '', query, flags=re.MULTILINE)

    # Replace string literals
    query = re.sub(r"'[^']*'", "'?'", query)

    # Replace numeric literals (but not in identifiers)
    query = re.sub(r'\b\d+\b', '?', query)

    # Replace IN lists
    query = re.sub(r'\bIN\s*\([^)]+\)', 'IN (?)', query, flags=re.IGNORECASE)

    # Collapse whitespace
    query = re.sub(r'\s+', ' ', query).strip()

    return query


def compute_query_signature(query: str) -> str:
    """Compute a hash signature for a normalized query."""
    normalized = normalize_query(query)
    return hashlib.md5(normalized.encode()).hexdigest()[:16]


# =============================================================================
# Database Collector
# =============================================================================

class DBMCollector:
    """Collects DBM-style data from PostgreSQL."""

    def __init__(self, config: Config):
        self.config = config
        self.conn = None
        self.explain_count = 0
        self.last_statements: Dict[int, Dict] = {}  # For computing deltas
        self.pg_version = None

    def connect(self) -> None:
        """Establish database connection."""
        try:
            self.conn = psycopg2.connect(
                host=self.config.pg_host,
                port=self.config.pg_port,
                user=self.config.pg_user,
                password=self.config.pg_password,
                database=self.config.pg_database,
                sslmode='require',
                connect_timeout=10,
            )
            self.conn.autocommit = True

            # Detect PostgreSQL version
            with self.conn.cursor() as cur:
                cur.execute("SHOW server_version")
                version_str = cur.fetchone()[0]
                # Extract major version (e.g., "11.22" -> 11, "15.4" -> 15)
                self.pg_version = int(version_str.split('.')[0])
                logger.info(f"Connected to PostgreSQL {self.pg_version} at {self.config.pg_host}:{self.config.pg_port}/{self.config.pg_database}")
        except Exception as e:
            logger.error(f"Failed to connect: {e}")
            raise

    def close(self) -> None:
        """Close database connection."""
        if self.conn:
            self.conn.close()
            self.conn = None

    def collect_query_samples(self) -> List[QuerySample]:
        """Collect active query samples from pg_stat_activity."""
        samples = []
        timestamp = datetime.now(timezone.utc).isoformat()

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Use the otel_monitor schema function if available, else direct query
                cur.execute("""
                    SELECT
                        pid,
                        datname as database,
                        usename as username,
                        application_name,
                        client_addr::text,
                        state,
                        wait_event_type,
                        wait_event,
                        left(query, 4096) as query,
                        EXTRACT(EPOCH FROM (now() - query_start)) * 1000 as duration_ms
                    FROM pg_stat_activity
                    WHERE state != 'idle'
                      AND pid != pg_backend_pid()
                      AND query NOT LIKE '%pg_stat_activity%'
                      AND backend_type = 'client backend'
                    ORDER BY duration_ms DESC
                    LIMIT 100
                """)

                for row in cur.fetchall():
                    if row['query']:
                        samples.append(QuerySample(
                            timestamp=timestamp,
                            database=row['database'] or '',
                            username=row['username'] or '',
                            pid=row['pid'],
                            query=row['query'],
                            query_signature=compute_query_signature(row['query']),
                            duration_ms=row['duration_ms'] or 0,
                            state=row['state'] or '',
                            wait_event_type=row['wait_event_type'],
                            wait_event=row['wait_event'],
                            client_addr=row['client_addr'],
                            application_name=row['application_name'],
                        ))

            logger.debug(f"Collected {len(samples)} query samples")

        except Exception as e:
            logger.error(f"Error collecting query samples: {e}")

        return samples

    def collect_query_metrics(self) -> List[QueryMetric]:
        """Collect query metrics from pg_stat_statements."""
        metrics = []
        timestamp = datetime.now(timezone.utc).isoformat()

        try:
            # Use version-appropriate column names
            # PostgreSQL 13+ uses total_exec_time, mean_exec_time
            # PostgreSQL 11-12 uses total_time, mean_time
            if self.pg_version >= 13:
                time_cols = "s.total_exec_time as total_time_ms, s.mean_exec_time as mean_time_ms"
                order_by = "s.total_exec_time DESC"
            else:
                time_cols = "s.total_time as total_time_ms, s.mean_time as mean_time_ms"
                order_by = "s.total_time DESC"

            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                query = f"""
                    SELECT
                        s.queryid,
                        d.datname as database,
                        pg_get_userbyid(s.userid) as username,
                        left(s.query, 4096) as query,
                        s.calls,
                        {time_cols},
                        s.rows,
                        s.shared_blks_hit,
                        s.shared_blks_read,
                        COALESCE(s.blk_read_time, 0) as blk_read_time_ms,
                        COALESCE(s.blk_write_time, 0) as blk_write_time_ms
                    FROM pg_stat_statements s
                    JOIN pg_database d ON d.oid = s.dbid
                    WHERE s.calls > 0
                      AND d.datname NOT IN ('template0', 'template1', 'rdsadmin')
                    ORDER BY {order_by}
                    LIMIT 200
                """
                cur.execute(query)

                for row in cur.fetchall():
                    metrics.append(QueryMetric(
                        timestamp=timestamp,
                        database=row['database'],
                        username=row['username'] or '',
                        query_id=row['queryid'],
                        query=row['query'],
                        query_signature=compute_query_signature(row['query']),
                        calls=row['calls'],
                        total_time_ms=row['total_time_ms'],
                        mean_time_ms=row['mean_time_ms'],
                        rows=row['rows'],
                        shared_blks_hit=row['shared_blks_hit'],
                        shared_blks_read=row['shared_blks_read'],
                        blk_read_time_ms=row['blk_read_time_ms'],
                        blk_write_time_ms=row['blk_write_time_ms'],
                    ))

            logger.debug(f"Collected {len(metrics)} query metrics")

        except Exception as e:
            logger.error(f"Error collecting query metrics: {e}")

        return metrics

    def collect_explain_plans(self, samples: List[QuerySample]) -> List[ExplainPlan]:
        """Collect EXPLAIN plans for sampled slow queries."""
        plans = []
        timestamp = datetime.now(timezone.utc).isoformat()
        self.explain_count = 0

        # Filter to slow queries
        slow_samples = [
            s for s in samples
            if s.duration_ms >= self.config.slow_query_threshold_ms
        ]

        for i, sample in enumerate(slow_samples):
            # Apply sampling rate
            if i % self.config.explain_sample_rate != 0:
                continue

            # Respect max explains per interval
            if self.explain_count >= self.config.max_explains_per_interval:
                break

            # Only explain SELECT, UPDATE, INSERT, DELETE
            query_upper = sample.query.upper().strip()
            if not any(query_upper.startswith(kw) for kw in ['SELECT', 'UPDATE', 'INSERT', 'DELETE']):
                continue

            try:
                with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                    # Use otel_monitor.explain_statement if available
                    cur.execute(
                        "SELECT * FROM otel_monitor.explain_statement(%s)",
                        (sample.query,)
                    )
                    result = cur.fetchone()

                    if result and result.get('explain'):
                        plans.append(ExplainPlan(
                            timestamp=timestamp,
                            database=sample.database,
                            query=sample.query,
                            query_signature=sample.query_signature,
                            plan=result['explain'],
                        ))
                        self.explain_count += 1

            except Exception as e:
                # Log but don't fail on explain errors
                logger.debug(f"Could not explain query: {e}")

        logger.debug(f"Collected {len(plans)} explain plans")
        return plans

    def collect_wait_events(self) -> List[WaitEvent]:
        """Collect wait event aggregations."""
        events = []
        timestamp = datetime.now(timezone.utc).isoformat()

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT
                        datname as database,
                        wait_event_type,
                        wait_event,
                        count(*) as count
                    FROM pg_stat_activity
                    WHERE wait_event IS NOT NULL
                      AND state = 'active'
                      AND backend_type = 'client backend'
                    GROUP BY datname, wait_event_type, wait_event
                    ORDER BY count DESC
                    LIMIT 50
                """)

                for row in cur.fetchall():
                    events.append(WaitEvent(
                        timestamp=timestamp,
                        database=row['database'] or '',
                        wait_event_type=row['wait_event_type'],
                        wait_event=row['wait_event'],
                        count=row['count'],
                    ))

            logger.debug(f"Collected {len(events)} wait events")

        except Exception as e:
            logger.error(f"Error collecting wait events: {e}")

        return events

    def collect_blocking_queries(self) -> List[BlockingQuery]:
        """Collect blocking query information."""
        blocking = []
        timestamp = datetime.now(timezone.utc).isoformat()

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Try using the view first
                try:
                    cur.execute("""
                        SELECT
                            database,
                            blocked_pid,
                            blocked_user,
                            left(blocked_query, 4096) as blocked_query,
                            blocking_pid,
                            blocking_user,
                            left(blocking_query, 4096) as blocking_query,
                            EXTRACT(EPOCH FROM (now() - blocked_query_start)) as blocked_duration_seconds,
                            lock_type
                        FROM otel_monitor.blocking_queries
                        LIMIT 50
                    """)
                except:
                    # Fallback to direct query
                    cur.execute("""
                        SELECT
                            blocked_activity.datname AS database,
                            blocked_locks.pid AS blocked_pid,
                            blocked_activity.usename AS blocked_user,
                            left(blocked_activity.query, 4096) AS blocked_query,
                            blocking_locks.pid AS blocking_pid,
                            blocking_activity.usename AS blocking_user,
                            left(blocking_activity.query, 4096) AS blocking_query,
                            EXTRACT(EPOCH FROM (now() - blocked_activity.query_start)) AS blocked_duration_seconds,
                            blocked_locks.locktype AS lock_type
                        FROM pg_catalog.pg_locks blocked_locks
                        JOIN pg_catalog.pg_stat_activity blocked_activity
                            ON blocked_activity.pid = blocked_locks.pid
                        JOIN pg_catalog.pg_locks blocking_locks
                            ON blocking_locks.locktype = blocked_locks.locktype
                            AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
                            AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
                            AND blocking_locks.pid != blocked_locks.pid
                        JOIN pg_catalog.pg_stat_activity blocking_activity
                            ON blocking_activity.pid = blocking_locks.pid
                        WHERE NOT blocked_locks.granted
                        LIMIT 50
                    """)

                for row in cur.fetchall():
                    blocking.append(BlockingQuery(
                        timestamp=timestamp,
                        database=row['database'] or '',
                        blocked_pid=row['blocked_pid'],
                        blocked_user=row['blocked_user'] or '',
                        blocked_query=row['blocked_query'] or '',
                        blocking_pid=row['blocking_pid'],
                        blocking_user=row['blocking_user'] or '',
                        blocking_query=row['blocking_query'] or '',
                        blocked_duration_seconds=row['blocked_duration_seconds'] or 0,
                        lock_type=row['lock_type'] or '',
                    ))

            logger.debug(f"Collected {len(blocking)} blocking queries")

        except Exception as e:
            logger.error(f"Error collecting blocking queries: {e}")

        return blocking

    def collect_all(self) -> Dict[str, Any]:
        """Collect all DBM data."""
        # Collect query samples first (used for explain plans)
        query_samples = self.collect_query_samples()

        return {
            'metadata': {
                'collector_version': '1.0.0',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'environment': self.config.environment,
                'rds_instance_id': self.config.rds_instance_id,
                'aws_region': self.config.aws_region,
                'database': self.config.pg_database,
            },
            'query_samples': [asdict(s) for s in query_samples],
            'query_metrics': [asdict(m) for m in self.collect_query_metrics()],
            'explain_plans': [asdict(p) for p in self.collect_explain_plans(query_samples)],
            'wait_events': [asdict(e) for e in self.collect_wait_events()],
            'blocking_queries': [asdict(b) for b in self.collect_blocking_queries()],
        }


# =============================================================================
# Output Formatters
# =============================================================================

def output_json(data: Dict[str, Any]) -> None:
    """Output data as JSON to stdout."""
    print(json.dumps(data, indent=2, default=str))


def setup_otlp_exporter(config: Config) -> metrics.Meter:
    """Setup OTLP exporter and return a meter for creating metrics."""
    # Parse auth header
    headers = {}
    if config.otlp_auth:
        if config.otlp_auth.startswith('Basic '):
            headers['Authorization'] = config.otlp_auth
        else:
            headers['Authorization'] = f'Basic {config.otlp_auth}'

    # Create resource with metadata
    resource = Resource.create({
        "service.name": "postgresql-dbm-collector",
        "deployment.environment": config.environment,
        "db.system": "postgresql",
        "db.instance.id": config.rds_instance_id,
        "cloud.provider": "aws",
        "cloud.platform": "aws_rds",
        "cloud.region": config.aws_region,
        "postgresql.database.name": config.pg_database,
    })

    # Create OTLP exporter
    exporter = OTLPMetricExporter(
        endpoint=f"{config.otlp_endpoint}/v1/metrics",
        headers=headers,
    )

    # Create metric reader with export interval matching collection interval
    reader = PeriodicExportingMetricReader(
        exporter,
        export_interval_millis=config.collection_interval * 1000,
    )

    # Create meter provider
    provider = MeterProvider(
        resource=resource,
        metric_readers=[reader],
    )

    # Set global meter provider
    metrics.set_meter_provider(provider)

    # Return meter for creating instruments
    return metrics.get_meter("postgresql.dbm")


def output_otlp(data: Dict[str, Any], meter: metrics.Meter) -> None:
    """Output data via OTLP to Last9."""

    # Create/get metric instruments (these are cached by name)
    query_calls = meter.create_counter(
        "postgresql.dbm.query.calls",
        description="Number of times the query was executed",
        unit="1",
    )

    query_total_time = meter.create_counter(
        "postgresql.dbm.query.total_time",
        description="Total execution time for the query",
        unit="ms",
    )

    query_mean_time = meter.create_gauge(
        "postgresql.dbm.query.mean_time",
        description="Mean execution time per call",
        unit="ms",
    )

    query_rows = meter.create_counter(
        "postgresql.dbm.query.rows",
        description="Total number of rows retrieved or affected",
        unit="1",
    )

    query_buffer_hits = meter.create_counter(
        "postgresql.dbm.query.buffer.hits",
        description="Shared blocks hit (buffer cache hits)",
        unit="1",
    )

    query_buffer_reads = meter.create_counter(
        "postgresql.dbm.query.buffer.reads",
        description="Shared blocks read from disk",
        unit="1",
    )

    query_io_read_time = meter.create_counter(
        "postgresql.dbm.query.io.read_time",
        description="Time spent reading blocks from disk",
        unit="ms",
    )

    query_io_write_time = meter.create_counter(
        "postgresql.dbm.query.io.write_time",
        description="Time spent writing blocks to disk",
        unit="ms",
    )

    active_queries = meter.create_gauge(
        "postgresql.dbm.active_queries",
        description="Number of active queries",
        unit="1",
    )

    wait_events_count = meter.create_gauge(
        "postgresql.dbm.wait_events",
        description="Number of processes waiting on events",
        unit="1",
    )

    blocking_queries_count = meter.create_gauge(
        "postgresql.dbm.blocking_queries",
        description="Number of blocking queries",
        unit="1",
    )

    query_info = meter.create_gauge(
        "postgresql.dbm.query_info",
        description="Query information mapping signature to query text",
        unit="1",
    )

    # Record query metrics from pg_stat_statements
    for metric in data.get('query_metrics', []):
        attributes = {
            "database": metric['database'],
            "username": metric['username'],
            "query_signature": metric['query_signature'],
        }

        # Record cumulative metrics
        query_calls.add(metric['calls'], attributes)
        query_total_time.add(metric['total_time_ms'], attributes)
        query_rows.add(metric['rows'], attributes)
        query_buffer_hits.add(metric['shared_blks_hit'], attributes)
        query_buffer_reads.add(metric['shared_blks_read'], attributes)
        query_io_read_time.add(metric['blk_read_time_ms'], attributes)
        query_io_write_time.add(metric['blk_write_time_ms'], attributes)

        # Record query info (mapping signature to query text)
        # Truncate query to avoid label size limits (max 200 chars)
        query_text = metric['query'][:200] if len(metric['query']) > 200 else metric['query']
        query_info.set(
            1,  # Always 1, this is just an info metric
            {
                "database": metric['database'],
                "username": metric['username'],
                "query_signature": metric['query_signature'],
                "query": query_text,
                "query_id": str(metric['query_id']),
            }
        )

    # Record active query count
    active_queries.set(
        len(data.get('query_samples', [])),
        {"database": data['metadata']['database']}
    )

    # Record wait events
    for event in data.get('wait_events', []):
        wait_events_count.set(
            event['count'],
            {
                "database": event['database'],
                "wait_event_type": event['wait_event_type'],
                "wait_event": event['wait_event'],
            }
        )

    # Record blocking queries count
    blocking_queries_count.set(
        len(data.get('blocking_queries', [])),
        {"database": data['metadata']['database']}
    )

    logger.info(
        f"Exported to OTLP: "
        f"{len(data.get('query_metrics', []))} query metrics, "
        f"{len(data.get('query_samples', []))} active queries, "
        f"{len(data.get('wait_events', []))} wait events, "
        f"{len(data.get('blocking_queries', []))} blocking queries"
    )


# =============================================================================
# Main Entry Point
# =============================================================================

def main():
    """Main entry point."""
    config = Config()
    collector = DBMCollector(config)
    meter = None

    # Setup OTLP exporter if needed
    if config.output_format == 'otlp':
        if not config.otlp_endpoint:
            logger.error("OTLP endpoint not configured. Set LAST9_OTLP_ENDPOINT environment variable.")
            sys.exit(1)

        logger.info(f"Setting up OTLP exporter to {config.otlp_endpoint}")
        meter = setup_otlp_exporter(config)

    try:
        collector.connect()

        while True:
            try:
                data = collector.collect_all()

                if config.output_format == 'json':
                    output_json(data)
                elif config.output_format == 'otlp':
                    output_otlp(data, meter)

                # Summary log
                logger.info(
                    f"Collected: "
                    f"{len(data['query_samples'])} samples, "
                    f"{len(data['query_metrics'])} metrics, "
                    f"{len(data['explain_plans'])} plans, "
                    f"{len(data['wait_events'])} wait events, "
                    f"{len(data['blocking_queries'])} blocking"
                )

            except Exception as e:
                logger.error(f"Collection error: {e}")

            time.sleep(config.collection_interval)

    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        collector.close()

        # Shutdown OTLP exporter gracefully
        if meter:
            provider = metrics.get_meter_provider()
            if hasattr(provider, 'shutdown'):
                logger.info("Shutting down OTLP exporter...")
                provider.shutdown()


if __name__ == '__main__':
    main()
