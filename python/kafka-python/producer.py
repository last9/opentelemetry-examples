"""
Test message generator — sends sample order messages to the input topic.

The auto-instrumentor (KafkaInstrumentor) automatically creates a PRODUCER span
and injects W3C traceparent into the message headers on every producer.send() call.
No manual inject() needed.

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

from kafka import KafkaProducer

from telemetry import init_tracing, shutdown_tracing

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
INPUT_TOPIC = os.environ.get("KAFKA_INPUT_TOPIC", "orders")

ITEMS = ["widget", "gadget", "doohickey", "thingamajig", "gizmo"]


def run() -> None:
    provider = init_tracing()

    # Auto-instrumented: every producer.send() creates a PRODUCER span and
    # injects traceparent into the message headers automatically.
    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
    )

    count = int(os.environ.get("MESSAGE_COUNT", "5"))
    delay = float(os.environ.get("MESSAGE_DELAY_SECONDS", "1.0"))

    try:
        for i in range(count):
            order = {
                "order_id": str(uuid.uuid4()),
                "item": random.choice(ITEMS),
                "amount": round(random.uniform(10.0, 500.0), 2),
                "currency": "USD",
            }
            producer.send(INPUT_TOPIC, value=order)
            logger.info(
                "Sent order %s — %s @ %.2f %s",
                order["order_id"], order["item"], order["amount"], order["currency"],
            )
            if i < count - 1:
                time.sleep(delay)
    finally:
        producer.flush()
        shutdown_tracing(provider)
        logger.info("Done — sent %d message(s).", count)


if __name__ == "__main__":
    run()
