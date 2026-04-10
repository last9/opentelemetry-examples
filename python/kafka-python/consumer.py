"""
Vanilla Python Kafka consumer with OpenTelemetry auto-instrumentation.

Uses kafka-python + opentelemetry-instrumentation-kafka, which automatically:
  - Creates a CONSUMER span for each message received
  - Extracts W3C traceparent from message headers (links to the producer's trace)
  - Creates a PRODUCER span when sending to the output topic
  - Injects W3C traceparent into outgoing message headers

Note on context propagation:
  kafka-python uses an iterator pattern. The auto-instrumentor creates the CONSUMER
  span inside __next__() and its context does not survive the yield boundary into
  user code. We therefore extract the context from msg.headers manually to attach
  business logic child spans to the correct trace. The Kafka-level CONSUMER/PRODUCER
  spans (transport layer) are still fully automatic.
"""

import json
import logging
import os
import signal
import time

from kafka import KafkaConsumer, KafkaProducer

from opentelemetry import trace
from opentelemetry.propagate import extract
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


def headers_to_carrier(headers) -> dict:
    """Convert Kafka message headers to an OTel text-map carrier."""
    if not headers:
        return {}
    return {k: v.decode("utf-8") for k, v in headers if v is not None}


def process_order(order: dict, tracer) -> dict:
    """Business logic: validate and process an order."""
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


def run() -> None:
    provider = init_tracing()
    tracer = trace.get_tracer(__name__)
    running = True

    # Auto-instrumented: KafkaConsumer and KafkaProducer are wrapped by
    # KafkaInstrumentor after init_tracing() is called.
    consumer = KafkaConsumer(
        INPUT_TOPIC,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id=CONSUMER_GROUP,
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        value_deserializer=lambda b: json.loads(b.decode("utf-8")),
    )

    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
    )

    def handle_shutdown(sig, frame):
        nonlocal running
        logger.info("Received signal %s — stopping after current message…", sig)
        running = False

    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGTERM, handle_shutdown)

    logger.info(
        "Subscribed to '%s', publishing results to '%s' (group=%s)",
        INPUT_TOPIC, OUTPUT_TOPIC, CONSUMER_GROUP,
    )

    try:
        for msg in consumer:
            if not running:
                break

            # The auto-instrumentor created a CONSUMER span inside __next__() but
            # its context doesn't survive the yield into user code. We extract
            # context from the message headers so our business logic spans are
            # correctly parented to the producer's trace.
            carrier = headers_to_carrier(msg.headers)
            ctx = extract(carrier)

            with tracer.start_as_current_span(
                f"{INPUT_TOPIC} process",
                context=ctx,
                kind=SpanKind.CONSUMER,
                attributes={
                    "messaging.system": "kafka",
                    "messaging.source.name": INPUT_TOPIC,
                    "messaging.operation.type": "process",
                    "messaging.message.offset": msg.offset,
                    "messaging.kafka.consumer.group": CONSUMER_GROUP,
                    "messaging.kafka.partition": msg.partition,
                },
            ) as span:
                try:
                    result = process_order(msg.value, tracer)

                    # send() is auto-instrumented: creates a PRODUCER span and
                    # injects traceparent into the outgoing message headers.
                    producer.send(OUTPUT_TOPIC, value=result)
                except Exception as exc:
                    logger.exception(
                        "Failed to process message at offset %d: %s",
                        msg.offset, exc,
                    )
                    span.record_exception(exc)
                    span.set_status(StatusCode.ERROR, str(exc))
    finally:
        consumer.close()
        producer.flush()
        shutdown_tracing(provider)
        logger.info("Consumer shut down cleanly.")


if __name__ == "__main__":
    run()
