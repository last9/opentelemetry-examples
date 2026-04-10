# Vanilla Python Kafka Consumer with OpenTelemetry

Plain Python service (no framework) that consumes messages from a Kafka topic,
processes them, and publishes results to another topic. Trace context is propagated
end-to-end via W3C `traceparent` headers on each Kafka message.

## How trace context flows

```
producer.py  ──[traceparent header]──▶  Kafka: orders
                                               │
                                          consumer.py
                                               │
                                       extract context
                                               │
                                     CONSUMER span (child of producer)
                                       │           │
                               process_order    PRODUCER span
                                  (child)            │
                                               inject context
                                               [traceparent header]
                                                     │
                                        Kafka: order-results ──▶ next service
```

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

This starts a single-node Kafka (KRaft, no Zookeeper) and the consumer service.

**4. Send test messages**

```bash
docker compose --profile generate up message-generator
```

Or run locally (with Kafka port-forwarded):

```bash
source .env && python producer.py
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otlp.last9.io` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | — | `Authorization=Basic <token>` |
| `OTEL_SERVICE_NAME` | `kafka-consumer` | Service name in traces |
| `SERVICE_VERSION` | `1.0.0` | `service.version` resource attribute |
| `DEPLOYMENT_ENVIRONMENT` | `development` | `deployment.environment` resource attribute |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka broker address |
| `KAFKA_INPUT_TOPIC` | `orders` | Topic to consume from |
| `KAFKA_OUTPUT_TOPIC` | `order-results` | Topic to publish results to |
| `KAFKA_CONSUMER_GROUP` | `order-processor` | Consumer group ID |
| `MESSAGE_COUNT` | `5` | Messages sent by `producer.py` |
| `MESSAGE_DELAY_SECONDS` | `1.0` | Delay between messages in `producer.py` |

## Running without Docker

Start Kafka separately, then:

```bash
# Port 29092 is the host-accessible listener (29092→Kafka external, 9092 is Docker-internal only)
export KAFKA_BOOTSTRAP_SERVERS=localhost:29092
source .env
python consumer.py          # terminal 1 — long-running consumer
python producer.py          # terminal 2 — sends 5 test messages
```

## Verification

Sign in to [Last9 Dashboard](https://app.last9.io) → APM → Traces. Filter by
`service.name = kafka-consumer`. You should see connected spans showing the full
producer → consumer → result-publisher chain within a single trace.
