# Flask + OpenTelemetry Instrumentation

This example demonstrates how to instrument a simple Flask application with
OpenTelemetry.

- Create a virtual environment and install the dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

- Install the Auto Instrumentation packages using the `opentelemetry-bootstrap`
  tool:

```bash
opentelemetry-bootstrap -a install
```

- Create a `.env` file with the following content:

```bash
OTEL_SERVICE_NAME=flask-app
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://otlp.last9.io/v1/traces
OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=<OBTAIN_AUTH_HEADER_FROM_LAST9_DASHBOARD>"
OTEL_TRACES_EXPORTER=console,otlp
OTEL_METRICS_EXPORTER=none
```

- Give permission to execute the `run.sh` script:

```bash
chmod +x run.sh
```

- Run the application:

```bash
./run.sh
```
