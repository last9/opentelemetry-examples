"""
Vanilla Python Kafka consumer with OpenTelemetry trace context propagation.

Reads orders from KAFKA_INPUT_TOPIC, processes them, and publishes results
to KAFKA_OUTPUT_TOPIC. Trace context travels across services via W3C
traceparent/tracestate headers on each Kafka message.

Trace flow:
  [producer] --[traceparent header]--> Kafka: orders
                                            |
                                       consumer.py
                                            |
                                    extract context   <-- W3C traceparent from headers
                                            |
                                  [CONSUMER span]     <-- child of producer's span
                                            |
                                  [process_order]     <-- child span (business logic)
                                            |
                                  [PRODUCER span]     <-- child span, inject new context
                                            |
                               Kafka: order-results --[traceparent header]--> next service
"""

import json
import logging
import os
import signal
import time

from confluent_kafka import Consumer, KafkaError, KafkaException, Producer

from opentelemetry import trace
from opentelemetry.propagate import extract, inject
from opentelemetry.trace import SpanKind, StatusCode

from telemetry import init_tracing, shutdown_tracing

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

BOOTSTRAP_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
INPUT_TOPIC = os.environ.get("KAFKA_INPUT_TOPIC", "orders")
OUTPUT_TOPIC = os.environ.get("KAFKA_OUTPUT_TOPIC", "order-results")
CONSUMER_GROUP = os.environ.get("KAFKA_CONSUMER_GROUP", "order-processor")


# ---------------------------------------------------------------------------
# Header helpers
# ---------------------------------------------------------------------------

def headers_to_carrier(headers: list) -> dict:
    """Convert Kafka message headers to an OTel text-map carrier."""
    if not headers:
        return {}
    return {k: v.decode("utf-8") for k, v in headers if v is not None}


def carrier_to_headers(carrier: dict) -> list:
    """Convert an OTel text-map carrier to Kafka message headers."""
    return [(k, v.encode("utf-8")) for k, v in carrier.items()]


# ---------------------------------------------------------------------------
# Business logic
# ---------------------------------------------------------------------------

def process_order(order: dict, tracer) -> dict:
    """Process an order and return a result dict."""
    with tracer.start_as_current_span("process_order") as span:
        order_id = order.get("order_id", "unknown")
        amount = float(order.get("amount", 0))

        span.set_attribute("order.id", order_id)
        span.set_attribute("order.amount", amount)
        span.set_attribute("order.item", order.get("item", ""))

        time.sleep(0.05)  # simulate processing work

        logger.info("Processed order %s (amount=%.2f)", order_id, amount)
        return {
            "order_id": order_id,
            "status": "processed",
            "processed_at": time.time(),
        }


# ---------------------------------------------------------------------------
# Output producer
# ---------------------------------------------------------------------------

def publish_result(kproducer: Producer, result: dict, tracer) -> None:
    """Publish a result to the output topic with trace context in headers."""
    with tracer.start_as_current_span(
        f"{OUTPUT_TOPIC} publish",
        kind=SpanKind.PRODUCER,
        attributes={
            "messaging.system": "kafka",
            "messaging.destination.name": OUTPUT_TOPIC,
            "messaging.operation.type": "publish",
            "order.id": result.get("order_id", ""),
        },
    ):
        carrier: dict = {}
        inject(carrier)  # captures the current PRODUCER span context
        headers = carrier_to_headers(carrier)

        kproducer.produce(
            topic=OUTPUT_TOPIC,
            value=json.dumps(result).encode("utf-8"),
            headers=headers,
        )
        kproducer.poll(0)  # trigger delivery callbacks (non-blocking)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run() -> None:
    provider = init_tracing()
    tracer = trace.get_tracer(__name__)
    running = True

    consumer = Consumer({
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "group.id": CONSUMER_GROUP,
        "auto.offset.reset": "earliest",
        "enable.auto.commit": True,
    })

    kproducer = Producer({"bootstrap.servers": BOOTSTRAP_SERVERS})

    def handle_shutdown(sig, frame):
        nonlocal running
        logger.info("Received signal %s — shutting down after current message…", sig)
        running = False

    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGTERM, handle_shutdown)

    consumer.subscribe([INPUT_TOPIC])
    logger.info(
        "Subscribed to '%s', publishing results to '%s' (group=%s)",
        INPUT_TOPIC, OUTPUT_TOPIC, CONSUMER_GROUP,
    )

    try:
        while running:
            msg = consumer.poll(timeout=1.0)
            if msg is None:
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                raise KafkaException(msg.error())

            # Extract W3C traceparent from Kafka message headers
            carrier = headers_to_carrier(msg.headers() or [])
            parent_ctx = extract(carrier)

            with tracer.start_as_current_span(
                f"{INPUT_TOPIC} receive",
                context=parent_ctx,
                kind=SpanKind.CONSUMER,
                attributes={
                    "messaging.system": "kafka",
                    "messaging.source.name": INPUT_TOPIC,
                    "messaging.operation.type": "receive",
                    "messaging.message.offset": msg.offset(),
                    "messaging.kafka.consumer.group": CONSUMER_GROUP,
                    "messaging.kafka.partition": msg.partition(),
                },
            ) as span:
                try:
                    payload = json.loads(msg.value().decode("utf-8"))
                    result = process_order(payload, tracer)
                    publish_result(kproducer, result, tracer)
                except Exception as exc:
                    logger.exception(
                        "Failed to process message at offset %d: %s",
                        msg.offset(), exc,
                    )
                    span.record_exception(exc)
                    span.set_status(StatusCode.ERROR, str(exc))
    finally:
        consumer.close()
        kproducer.flush(timeout=5)
        shutdown_tracing(provider)
        logger.info("Consumer shut down cleanly.")


if __name__ == "__main__":
    run()
