"""
Test message generator — sends sample order messages to the input topic
with W3C trace context injected into Kafka headers.

Run this to generate messages for the consumer:
    python producer.py

Environment variables:
    MESSAGE_COUNT         — number of messages to send (default: 5)
    MESSAGE_DELAY_SECONDS — delay between messages in seconds (default: 1.0)
"""

import json
import logging
import os
import random
import time
import uuid

from confluent_kafka import Producer as KafkaProducer

from opentelemetry import trace
from opentelemetry.propagate import inject
from opentelemetry.trace import SpanKind

from telemetry import init_tracing, shutdown_tracing

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
INPUT_TOPIC = os.environ.get("KAFKA_INPUT_TOPIC", "orders")

ITEMS = ["widget", "gadget", "doohickey", "thingamajig", "gizmo"]


def send_order(kproducer: KafkaProducer, tracer) -> None:
    order = {
        "order_id": str(uuid.uuid4()),
        "item": random.choice(ITEMS),
        "amount": round(random.uniform(10.0, 500.0), 2),
        "currency": "USD",
    }

    with tracer.start_as_current_span(
        f"{INPUT_TOPIC} publish",
        kind=SpanKind.PRODUCER,
        attributes={
            "messaging.system": "kafka",
            "messaging.destination.name": INPUT_TOPIC,
            "messaging.operation.type": "publish",
            "order.id": order["order_id"],
            "order.item": order["item"],
            "order.amount": order["amount"],
        },
    ):
        carrier: dict = {}
        inject(carrier)  # inject current PRODUCER span context into carrier
        headers = [(k, v.encode("utf-8")) for k, v in carrier.items()]

        kproducer.produce(
            topic=INPUT_TOPIC,
            value=json.dumps(order).encode("utf-8"),
            headers=headers,
        )
        kproducer.poll(0)

        logger.info(
            "Sent order %s — %s @ %.2f %s",
            order["order_id"], order["item"], order["amount"], order["currency"],
        )


def run() -> None:
    provider = init_tracing()
    tracer = trace.get_tracer(__name__)

    kproducer = KafkaProducer({"bootstrap.servers": BOOTSTRAP_SERVERS})

    count = int(os.environ.get("MESSAGE_COUNT", "5"))
    delay = float(os.environ.get("MESSAGE_DELAY_SECONDS", "1.0"))

    try:
        for i in range(count):
            send_order(kproducer, tracer)
            if i < count - 1:
                time.sleep(delay)
    finally:
        kproducer.flush(timeout=5)
        shutdown_tracing(provider)
        logger.info("Done — sent %d message(s).", count)


if __name__ == "__main__":
    run()
