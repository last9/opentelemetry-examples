# Python Kafka Consumer with OpenTelemetry Auto-Instrumentation

Plain Python service (no framework) that consumes messages from a Kafka topic,
processes them, and publishes results to another topic. Uses
[`opentelemetry-instrumentation-kafka-python`](https://pypi.org/project/opentelemetry-instrumentation-kafka-python/)
to automatically propagate trace context — no manual `inject`/`extract` calls needed.

## How it works

A single call to `KafkaInstrumentor().instrument()` wraps all `KafkaProducer` and
`KafkaConsumer` instances:

- **Producer** — every `producer.send()` automatically creates a `PRODUCER` span
  and injects `traceparent` into message headers. No manual code needed.
- **Consumer (transport layer)** — auto-instrumented: creates a `CONSUMER` span and
  extracts `traceparent` from headers.
- **Consumer (business logic)** — `kafka-python` uses an iterator pattern; the
  auto-instrumentor creates its span inside `__next__()` and the context doesn't
  survive the yield into user code. We extract context from `msg.headers` manually
  to parent business logic spans correctly. The Kafka send/receive spans themselves
  remain fully automatic.

## Trace flow

```
producer.py     │  orders (send)           (PRODUCER) ← auto-created, headers injected
kafka-python    │  orders (receive)        (CONSUMER) ← auto-created, headers extracted
kafka-python    │    process_order         (INTERNAL) ← manual child span
kafka-python    │    order-results (send)  (PRODUCER) ← auto-created, headers injected
```

## vs. confluent-kafka example

| | `kafka-python` (this example) | `confluent-kafka` |
|---|---|---|
| Auto-instrumentation | Yes — `KafkaInstrumentor` | No official package |
| Header propagation | Automatic | Manual `inject`/`extract` |
| Code complexity | Lower | Higher |

## Prerequisites

- Python 3.11+
- Docker and Docker Compose (for local Kafka)

## Quick Start

**1. Install dependencies**

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**2. Configure credentials**

```bash
cp .env.example .env
```

Edit `.env` — set your Last9 OTLP endpoint and auth header. Get them from
[app.last9.io](https://app.last9.io) → Integrations → OpenTelemetry.

**3. Start Kafka and the consumer**

```bash
docker compose up --build
```

**4. Send test messages**

```bash
docker compose --profile generate up message-generator
```

Or run locally (Kafka port-forwarded on `29093`):

```bash
export KAFKA_BOOTSTRAP_SERVERS=localhost:29093
source .env
python producer.py
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otlp.last9.io` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | — | `Authorization=Basic <token>` |
| `OTEL_SERVICE_NAME` | `kafka-python-consumer` | Service name in traces |
| `SERVICE_VERSION` | `1.0.0` | `service.version` resource attribute |
| `DEPLOYMENT_ENVIRONMENT` | `development` | `deployment.environment` resource attribute |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka broker address |
| `KAFKA_INPUT_TOPIC` | `orders` | Topic to consume from |
| `KAFKA_OUTPUT_TOPIC` | `order-results` | Topic to publish results to |
| `KAFKA_CONSUMER_GROUP` | `order-processor` | Consumer group ID |
| `MESSAGE_COUNT` | `5` | Messages sent by `producer.py` |
| `MESSAGE_DELAY_SECONDS` | `1.0` | Delay between messages in `producer.py` |

## Verification

Sign in to [Last9 Dashboard](https://app.last9.io) → APM → Traces. Filter by
`service.name = kafka-python-consumer`. You should see connected spans showing
the full producer → consumer → result-publisher chain within a single trace.
