"""
Lambda handler that extracts trace context from SQS Event Source Mapping records.

When Lambda is triggered via SQS ESM, messageAttributes arrive in a different
format than the SDK's ReceiveMessage response:

    ESM format:   {"traceparent": {"stringValue": "00-...", "dataType": "String"}}
    SDK format:   {"traceparent": {"StringValue": "00-...", "DataType": "String"}}

This handler normalizes the ESM format and extracts W3C traceparent/tracestate
to create child spans linked to the producer's trace.
"""

import json
import logging
import time

from opentelemetry import trace
from opentelemetry.propagate import extract
from opentelemetry.trace import SpanKind, Link

logger = logging.getLogger()
logger.setLevel(logging.INFO)

tracer = trace.get_tracer(__name__)


def extract_context_from_sqs_record(record: dict):
    """Extract OTel context from an SQS ESM record's messageAttributes.

    SQS Event Source Mapping delivers attributes with lowercase keys:
        {"traceparent": {"stringValue": "...", "dataType": "String"}}

    We normalize these into a flat dict for the OTel propagator.
    """
    carrier = {}
    # Support both Lambda ESM ("messageAttributes") and SDK ReceiveMessage ("MessageAttributes")
    msg_attrs = record.get("messageAttributes") or record.get("MessageAttributes") or {}
    for key, attr in msg_attrs.items():
        # ESM uses lowercase "stringValue"; SDK uses "StringValue"
        value = attr.get("stringValue") if "stringValue" in attr else attr.get("StringValue")
        if value is not None:
            carrier[key] = value
    return extract(carrier)


def process_record(record: dict):
    """Process a single SQS record with trace context linking."""
    ctx = extract_context_from_sqs_record(record)

    body = json.loads(record.get("body", "{}"))
    message_id = record.get("messageId", "unknown")
    queue_arn = record.get("eventSourceARN", "")
    queue_name = queue_arn.split(":")[-1] if queue_arn else "unknown"

    with tracer.start_as_current_span(
        f"process {queue_name}",
        context=ctx,
        kind=SpanKind.CONSUMER,
        attributes={
            "messaging.system": "aws_sqs",
            "messaging.source.name": queue_name,
            "messaging.operation.type": "process",
            "messaging.message.id": message_id,
        },
    ) as span:
        logger.info("Processing message %s: %s", message_id, body)

        # --- Your business logic here ---
        with tracer.start_as_current_span("business_logic") as child:
            time.sleep(0.05)  # Simulate work
            child.set_attribute("record.body", json.dumps(body)[:256])

        return {"messageId": message_id, "status": "processed"}


def handler(event, context):
    """Lambda entry point for SQS Event Source Mapping trigger.

    Each invocation may contain a batch of SQS records. We process each
    record individually, extracting trace context per message.
    """
    records = event.get("Records", [])
    logger.info("Received %d SQS record(s)", len(records))

    results = []
    failures = []

    for record in records:
        try:
            result = process_record(record)
            results.append(result)
        except Exception as e:
            logger.error("Failed to process message %s: %s", record.get("messageId"), e)
            failures.append({"itemIdentifier": record.get("messageId")})

    response = {"statusCode": 200, "processed": len(results)}

    # Partial batch failure reporting (requires ReportBatchItemFailures on ESM)
    if failures:
        response["batchItemFailures"] = failures

    return response
