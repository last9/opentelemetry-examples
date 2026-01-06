#!/usr/bin/env python3
"""
RDS CloudWatch Metrics Collector for Last9
Collects RDS host-level metrics from CloudWatch and exports via OTLP.

Metrics collected:
- CPU Utilization
- Memory (Freeable Memory, Swap Usage)
- Storage (Free Storage Space)
- IOPS (Read/Write IOPS, Read/Write Throughput)
- Latency (Read/Write Latency)
- Connections (Database Connections)
- Network (Network Receive/Transmit Throughput)
- Disk Queue Depth
"""

import os
import sys
import time
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any, Optional
from dataclasses import dataclass
import boto3
from botocore.exceptions import ClientError

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
logger = logging.getLogger('cloudwatch-collector')

# =============================================================================
# Configuration
# =============================================================================

@dataclass
class Config:
    """Collector configuration from environment variables."""
    # AWS Configuration
    aws_region: str = os.getenv('AWS_REGION', 'us-east-1')
    rds_instance_id: str = os.getenv('RDS_INSTANCE_ID', '')

    # Collection settings
    collection_interval: int = int(os.getenv('COLLECTION_INTERVAL', '60'))
    cloudwatch_period: int = int(os.getenv('CLOUDWATCH_PERIOD', '60'))  # CloudWatch metric period

    # OTLP settings
    otlp_endpoint: str = os.getenv('LAST9_OTLP_ENDPOINT', '')
    otlp_auth: str = os.getenv('LAST9_AUTH_HEADER', '')

    # Metadata
    environment: str = os.getenv('ENVIRONMENT', 'unknown')


# =============================================================================
# CloudWatch Metrics Definition
# =============================================================================

RDS_METRICS = [
    # CPU Metrics
    {'name': 'CPUUtilization', 'stat': 'Average', 'unit': 'Percent'},
    {'name': 'CPUCreditUsage', 'stat': 'Average', 'unit': 'Count'},
    {'name': 'CPUCreditBalance', 'stat': 'Average', 'unit': 'Count'},

    # Memory Metrics
    {'name': 'FreeableMemory', 'stat': 'Average', 'unit': 'Bytes'},
    {'name': 'SwapUsage', 'stat': 'Average', 'unit': 'Bytes'},

    # Storage Metrics
    {'name': 'FreeStorageSpace', 'stat': 'Average', 'unit': 'Bytes'},

    # IOPS Metrics
    {'name': 'ReadIOPS', 'stat': 'Average', 'unit': 'Count/Second'},
    {'name': 'WriteIOPS', 'stat': 'Average', 'unit': 'Count/Second'},

    # Throughput Metrics
    {'name': 'ReadThroughput', 'stat': 'Average', 'unit': 'Bytes/Second'},
    {'name': 'WriteThroughput', 'stat': 'Average', 'unit': 'Bytes/Second'},

    # Latency Metrics
    {'name': 'ReadLatency', 'stat': 'Average', 'unit': 'Seconds'},
    {'name': 'WriteLatency', 'stat': 'Average', 'unit': 'Seconds'},

    # Connection Metrics
    {'name': 'DatabaseConnections', 'stat': 'Average', 'unit': 'Count'},

    # Network Metrics
    {'name': 'NetworkReceiveThroughput', 'stat': 'Average', 'unit': 'Bytes/Second'},
    {'name': 'NetworkTransmitThroughput', 'stat': 'Average', 'unit': 'Bytes/Second'},

    # Queue Depth
    {'name': 'DiskQueueDepth', 'stat': 'Average', 'unit': 'Count'},

    # Replication Lag (if applicable)
    {'name': 'ReplicaLag', 'stat': 'Average', 'unit': 'Seconds'},
]


# =============================================================================
# CloudWatch Collector
# =============================================================================

class CloudWatchCollector:
    """Collects RDS metrics from CloudWatch."""

    def __init__(self, config: Config):
        self.config = config
        self.cloudwatch = None

    def connect(self) -> None:
        """Initialize CloudWatch client."""
        try:
            self.cloudwatch = boto3.client(
                'cloudwatch',
                region_name=self.config.aws_region
            )
            logger.info(f"Connected to CloudWatch in {self.config.aws_region}")
        except Exception as e:
            logger.error(f"Failed to connect to CloudWatch: {e}")
            raise

    def collect_metrics(self) -> Dict[str, Optional[float]]:
        """Collect all RDS metrics from CloudWatch."""
        metrics_data = {}

        # Calculate time range for CloudWatch query
        end_time = datetime.now(timezone.utc)
        start_time = end_time - timedelta(seconds=self.config.cloudwatch_period * 2)

        for metric_def in RDS_METRICS:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='AWS/RDS',
                    MetricName=metric_def['name'],
                    Dimensions=[
                        {
                            'Name': 'DBInstanceIdentifier',
                            'Value': self.config.rds_instance_id
                        }
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=self.config.cloudwatch_period,
                    Statistics=[metric_def['stat']]
                )

                # Get the most recent data point
                if response['Datapoints']:
                    # Sort by timestamp and get the latest
                    datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'], reverse=True)
                    value = datapoints[0].get(metric_def['stat'])
                    metrics_data[metric_def['name']] = value
                    logger.debug(f"{metric_def['name']}: {value} {metric_def['unit']}")
                else:
                    metrics_data[metric_def['name']] = None
                    logger.debug(f"{metric_def['name']}: No data available")

            except ClientError as e:
                logger.warning(f"Failed to collect {metric_def['name']}: {e}")
                metrics_data[metric_def['name']] = None
            except Exception as e:
                logger.error(f"Error collecting {metric_def['name']}: {e}")
                metrics_data[metric_def['name']] = None

        return metrics_data


# =============================================================================
# OTLP Exporter
# =============================================================================

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
        "service.name": "rds-cloudwatch-collector",
        "deployment.environment": config.environment,
        "db.system": "postgresql",
        "db.instance.id": config.rds_instance_id,
        "cloud.provider": "aws",
        "cloud.platform": "aws_rds",
        "cloud.region": config.aws_region,
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
    return metrics.get_meter("rds.cloudwatch")


def export_metrics(meter: metrics.Meter, metrics_data: Dict[str, Optional[float]], config: Config) -> None:
    """Export CloudWatch metrics via OTLP."""

    base_attributes = {
        "db_instance_id": config.rds_instance_id,
        "cloud_region": config.aws_region,
        "environment": config.environment,
    }

    # CPU Metrics
    if metrics_data.get('CPUUtilization') is not None:
        cpu_util = meter.create_gauge("rds.cpu.utilization", unit="%")
        cpu_util.set(metrics_data['CPUUtilization'], base_attributes)

    if metrics_data.get('CPUCreditUsage') is not None:
        cpu_credit_usage = meter.create_gauge("rds.cpu.credit_usage", unit="1")
        cpu_credit_usage.set(metrics_data['CPUCreditUsage'], base_attributes)

    if metrics_data.get('CPUCreditBalance') is not None:
        cpu_credit_balance = meter.create_gauge("rds.cpu.credit_balance", unit="1")
        cpu_credit_balance.set(metrics_data['CPUCreditBalance'], base_attributes)

    # Memory Metrics
    if metrics_data.get('FreeableMemory') is not None:
        freeable_memory = meter.create_gauge("rds.memory.freeable", unit="By")
        freeable_memory.set(metrics_data['FreeableMemory'], base_attributes)

    if metrics_data.get('SwapUsage') is not None:
        swap_usage = meter.create_gauge("rds.memory.swap_usage", unit="By")
        swap_usage.set(metrics_data['SwapUsage'], base_attributes)

    # Storage Metrics
    if metrics_data.get('FreeStorageSpace') is not None:
        free_storage = meter.create_gauge("rds.storage.free", unit="By")
        free_storage.set(metrics_data['FreeStorageSpace'], base_attributes)

    # IOPS Metrics
    if metrics_data.get('ReadIOPS') is not None:
        read_iops = meter.create_gauge("rds.iops.read", unit="1/s")
        read_iops.set(metrics_data['ReadIOPS'], base_attributes)

    if metrics_data.get('WriteIOPS') is not None:
        write_iops = meter.create_gauge("rds.iops.write", unit="1/s")
        write_iops.set(metrics_data['WriteIOPS'], base_attributes)

    # Throughput Metrics
    if metrics_data.get('ReadThroughput') is not None:
        read_throughput = meter.create_gauge("rds.throughput.read", unit="By/s")
        read_throughput.set(metrics_data['ReadThroughput'], base_attributes)

    if metrics_data.get('WriteThroughput') is not None:
        write_throughput = meter.create_gauge("rds.throughput.write", unit="By/s")
        write_throughput.set(metrics_data['WriteThroughput'], base_attributes)

    # Latency Metrics
    if metrics_data.get('ReadLatency') is not None:
        read_latency = meter.create_gauge("rds.latency.read", unit="s")
        read_latency.set(metrics_data['ReadLatency'], base_attributes)

    if metrics_data.get('WriteLatency') is not None:
        write_latency = meter.create_gauge("rds.latency.write", unit="s")
        write_latency.set(metrics_data['WriteLatency'], base_attributes)

    # Connection Metrics
    if metrics_data.get('DatabaseConnections') is not None:
        db_connections = meter.create_gauge("rds.connections", unit="1")
        db_connections.set(metrics_data['DatabaseConnections'], base_attributes)

    # Network Metrics
    if metrics_data.get('NetworkReceiveThroughput') is not None:
        network_rx = meter.create_gauge("rds.network.receive_throughput", unit="By/s")
        network_rx.set(metrics_data['NetworkReceiveThroughput'], base_attributes)

    if metrics_data.get('NetworkTransmitThroughput') is not None:
        network_tx = meter.create_gauge("rds.network.transmit_throughput", unit="By/s")
        network_tx.set(metrics_data['NetworkTransmitThroughput'], base_attributes)

    # Queue Depth
    if metrics_data.get('DiskQueueDepth') is not None:
        disk_queue = meter.create_gauge("rds.disk.queue_depth", unit="1")
        disk_queue.set(metrics_data['DiskQueueDepth'], base_attributes)

    # Replication Lag (if applicable)
    if metrics_data.get('ReplicaLag') is not None:
        replica_lag = meter.create_gauge("rds.replication.lag", unit="s")
        replica_lag.set(metrics_data['ReplicaLag'], base_attributes)

    # Count non-null metrics
    collected_count = sum(1 for v in metrics_data.values() if v is not None)
    logger.info(f"Exported {collected_count}/{len(RDS_METRICS)} CloudWatch metrics to OTLP")


# =============================================================================
# Main Entry Point
# =============================================================================

def main():
    """Main entry point."""
    config = Config()

    # Validate configuration
    if not config.rds_instance_id:
        logger.error("RDS_INSTANCE_ID environment variable is required")
        sys.exit(1)

    if not config.otlp_endpoint:
        logger.error("LAST9_OTLP_ENDPOINT environment variable is required")
        sys.exit(1)

    # Setup OTLP exporter
    logger.info(f"Setting up OTLP exporter to {config.otlp_endpoint}")
    meter = setup_otlp_exporter(config)

    # Initialize CloudWatch collector
    collector = CloudWatchCollector(config)

    try:
        collector.connect()

        while True:
            try:
                # Collect metrics from CloudWatch
                metrics_data = collector.collect_metrics()

                # Export to OTLP
                export_metrics(meter, metrics_data, config)

            except Exception as e:
                logger.error(f"Collection error: {e}")

            time.sleep(config.collection_interval)

    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        # Shutdown OTLP exporter gracefully
        provider = metrics.get_meter_provider()
        if hasattr(provider, 'shutdown'):
            logger.info("Shutting down OTLP exporter...")
            provider.shutdown()


if __name__ == '__main__':
    main()
