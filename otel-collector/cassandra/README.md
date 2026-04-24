# Cassandra + OTel Collector

Collects Cassandra JMX metrics via the `opentelemetry-jmx-metrics` JAR and ships to Last9.

## Prerequisites

- Apache Cassandra 4.x with JMX exposed on port 7199
- Java 17+ on the machine running the JMX metrics collector
- OTel Collector with OTLP receiver
- Last9 OTLP credentials

## Quick Start (local Docker test)

```bash
cp .env.example .env
# Fill in OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION
docker compose up -d
```

The Docker Compose setup uses a JMX metrics sidecar container (`eclipse-temurin:17-jre-jammy`) that collects JMX metrics from Cassandra and forwards them to the OTel Collector via OTLP.

## Production Setup (bare-metal)

### 1. Download the JMX metrics JAR

```bash
sudo wget -O /opt/opentelemetry-jmx-metrics.jar \
  https://github.com/open-telemetry/opentelemetry-java-contrib/releases/download/v1.43.0/opentelemetry-jmx-metrics.jar
```

### 2. Create the JMX config

Create `/etc/otelcol-contrib/jmx-config.properties`:

```properties
otel.exporter.otlp.endpoint = http://localhost:4317
otel.jmx.interval.milliseconds = 60000
otel.jmx.service.url = service:jmx:rmi:///jndi/rmi://localhost:7199/jmxrmi
otel.jmx.target.system = cassandra
otel.metrics.exporter = otlp
```

### 3. Run the JMX metrics JAR as a service

Create `/etc/systemd/system/cassandra-jmx-metrics.service`:

```ini
[Unit]
Description=Cassandra JMX Metrics Collector
After=cassandra.service

[Service]
ExecStart=java -jar /opt/opentelemetry-jmx-metrics.jar -config /etc/otelcol-contrib/jmx-config.properties
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cassandra-jmx-metrics
```

### 4. Install and configure OTel Collector

```bash
# AMD64
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.144.0_linux_amd64.deb
# ARM64
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.144.0/otelcol-contrib_0.144.0_linux_arm64.deb
sudo dpkg -i otelcol-contrib_0.144.0_linux_arm64.deb
```

```bash
sudo cp otel-collector-config.yaml /etc/otelcol-contrib/config.yaml
sudo systemctl enable --now otelcol-contrib
```

## Cassandra JMX Configuration

JMX is enabled on port 7199 by default. To allow remote JMX access:

Add to `/etc/cassandra/cassandra-env.sh` or JVM options:

```
-Dcom.sun.management.jmxremote
-Dcom.sun.management.jmxremote.port=7199
-Dcom.sun.management.jmxremote.rmi.port=7199
-Dcom.sun.management.jmxremote.ssl=false
-Dcom.sun.management.jmxremote.authenticate=false
-Djava.rmi.server.hostname=<your-cassandra-ip>
```

## Configuration

| Variable | Description |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Last9 OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS_AUTHORIZATION` | Last9 Basic auth header |

## Metrics Collected

- Read/write request latency (p50, p99, max)
- Request counts and error counts by operation
- Pending and completed compaction tasks
- Storage load and hints counts
- System CPU, memory, disk, network via `hostmetrics`
