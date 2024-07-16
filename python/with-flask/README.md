# Auto instrumentating Flask application using OpenTelemetry

This example demonstrates how to instrument a simple Flask application with
OpenTelemetry.

1. Create a virtual environment and install the dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Install the Auto Instrumentation packages using the `opentelemetry-bootstrap`
   tool:

```bash
opentelemetry-bootstrap -a install
```

3. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

4. Next, run the commands below to set the environment variables.

```bash
export OTEL_SERVICE_NAME=flask-app
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=<BASIC_AUTH_HEADER>"
export OTEL_TRACES_EXPORTER=console,otlp
export OTEL_METRICS_EXPORTER=otlp
```

> Note: `BASIC_AUTH_HEADER` should be replaced with the URL encoded value of the
> basic authorization header.

5. Run the Flask application:

```bash
opentelemetry-instrument flask run
```

6. Once the server is running, you can access the application at
   `http://127.0.0.1:5000` by default. Where you can make CRUD operations. The
   API endpoints are:

- GET `/users` - Get all users
- GET `/users/:id` - Get a user by ID
- POST `/users` - Create a new user
- PUT `/users/:id` - Update a user
- DELETE `/users/:id` - Delete a user

- GET `/products` - Get all products
- GET `/products/:id` - Get a product by ID
- POST `/products` - Create a new product

6. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces and metrics in action.
