"""
SQS Producer with OpenTelemetry trace context propagation.

Sends messages to SQS with W3C traceparent/tracestate injected into
MessageAttributes so downstream consumers (e.g., Lambda via SQS ESM)
can link their spans to the same trace.
"""

import json
import os
import logging

import boto3
from opentelemetry import trace, context
from opentelemetry.propagate import inject
from opentelemetry.propagators.textmap import CarrierT

logger = logging.getLogger(__name__)

sqs = boto3.client(
    "sqs",
    region_name=os.environ.get("AWS_REGION", "us-east-1"),
    endpoint_url=os.environ.get("AWS_ENDPOINT_URL"),  # For LocalStack
)

QUEUE_URL = os.environ["SQS_QUEUE_URL"]
tracer = trace.get_tracer(__name__)


def inject_trace_context() -> dict:
    """Inject current trace context into a dict suitable for SQS MessageAttributes."""
    carrier: CarrierT = {}
    inject(carrier)

    message_attributes = {}
    for key, value in carrier.items():
        message_attributes[key] = {
            "DataType": "String",
            "StringValue": value,
        }
    return message_attributes


def send_message(payload: dict) -> dict:
    """Send a message to SQS with trace context in MessageAttributes."""
    with tracer.start_as_current_span(
        "send_to_sqs",
        kind=trace.SpanKind.PRODUCER,
        attributes={
            "messaging.system": "aws_sqs",
            "messaging.destination.name": QUEUE_URL.rstrip("/").split("/")[-1],
            "messaging.operation.type": "publish",
        },
    ) as span:
        trace_attrs = inject_trace_context()

        body = json.dumps(payload)
        response = sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=body,
            MessageAttributes=trace_attrs,
        )

        message_id = response.get("MessageId", "")
        span.set_attribute("messaging.message.id", message_id)
        logger.info("Sent SQS message %s with trace context", message_id)

        return response
