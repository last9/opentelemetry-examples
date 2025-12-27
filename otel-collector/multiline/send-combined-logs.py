#!/usr/bin/env python3
"""
Send combined HAProxy logs to OTEL Collector via OTLP
Simulates customer sending logs with multiple lines in one record
"""

import time
from opentelemetry import _logs
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter

# Configure OTLP exporter pointing to local collector
exporter = OTLPLogExporter(
    endpoint="http://localhost:4317",
    insecure=True  # Use insecure connection for local testing
)

# Setup logger provider with resource
resource = Resource.create({
    "service.name": "haproxy-customer",
    "deployment.environment": "production"
})

logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
_logs.set_logger_provider(logger_provider)

# Get logger
logger = _logs.get_logger(__name__)

# Combined HAProxy logs (2 lines in one record - the problem!)
combined_log_1 = """2025-12-14T02:23:07.305817+00:00 ip-192-168-6-48 haproxy[927]: [WARNING]  (927) : Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed, code: 200, check duration: 10ms. 8 active and 0 backup servers online. 0 sessions requeued, 0 total in queue.
2025-12-14T02:23:07.305939+00:00 ip-192-168-6-48 haproxy[927]: Server rest-ra-backend/local_5008 is UP, reason: Layer7 check passed, code: 200, check duration: 10ms. 8 active and 0 backup servers online. 0 sessions requeued, 0 total in queue."""

combined_log_2 = """2025-12-14T10:15:23.123456+00:00 ip-192-168-6-48 haproxy[927]: [ERROR] Backend rest-ra-backend has no server available!
2025-12-14T10:15:23.123789+00:00 ip-192-168-6-48 haproxy[927]: [INFO] Retrying backend connection
2025-12-14T10:15:23.124001+00:00 ip-192-168-6-48 haproxy[927]: [INFO] Backend connection established"""

print("Sending combined HAProxy logs to OTEL Collector...")
print("=" * 80)

# Send first combined log (2 lines in 1 record)
print("\n[1] Sending combined log with 2 lines...")
print(f"Body:\n{combined_log_1}\n")
logger.emit(
    _logs.LogRecord(
        timestamp=int(time.time() * 1e9),
        body=combined_log_1,
        severity_number=_logs.SeverityNumber.WARN,
        attributes={"log.source": "haproxy", "environment": "production"}
    )
)
print("✓ Sent (should split into 2 records by collector)")

time.sleep(1)

# Send second combined log (3 lines in 1 record)
print("\n[2] Sending combined log with 3 lines...")
print(f"Body:\n{combined_log_2}\n")
logger.emit(
    _logs.LogRecord(
        timestamp=int(time.time() * 1e9),
        body=combined_log_2,
        severity_number=_logs.SeverityNumber.ERROR,
        attributes={"log.source": "haproxy", "environment": "production"}
    )
)
print("✓ Sent (should split into 3 records by collector)")

# Flush and wait
logger_provider.force_flush()
time.sleep(2)

print("\n" + "=" * 80)
print("✓ All logs sent successfully")
print("\nCheck collector output:")
print("  docker logs otel-collector-haproxy | grep -A 10 'LogRecord #'")
print("\nExpected: 5 total LogRecords (2 from first + 3 from second)")
