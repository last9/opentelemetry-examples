# Instrumentating Google cloud function using OpenTelemetry

This example demonstrates how to instrument a Google cloud function with OpenTelemetry.

1. Create a virtual environment and install the dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Install the Auto Instrumentation packages using the `opentelemetry-bootstrap`
   tool:

```bash
opentelemetry-bootstrap -a requirements
```
It will output the packages that you can add to `requirements.txt`.

```bash
opentelemetry-api>=1.15.0
opentelemetry-sdk>=1.15.0
opentelemetry-exporter-otlp>=1.15.0
opentelemetry-distro==0.48b0
opentelemetry-instrumentation==0.51b0
opentelemetry-instrumentation-aiohttp-client==0.51b0
opentelemetry-instrumentation-asyncio==0.51b0
```

3. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io) and update the code.

4. Run the application:

```bash
functions-framework --target http_handler --debug
```

5. Once the server is running, you can access the application at
   `http://127.0.0.1:8080` by default. 

6. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces in action.

![Traces](./traces.png)