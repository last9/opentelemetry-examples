# Auto instrumentating Roda application using OpenTelemetry

This example demonstrates how to instrument a simple Roda application
with OpenTelemetry.

1. Install the packages using following command:

```bash
bundle install
```

2. Obtain the OTLP Auth Header from the [Last9 dashboard](https://app.last9.io).
   The Auth header is required in the next step.

3. Next, run the commands below to set the environment variables.

```bash
touch .env
cp .env.example .env
```

4. In the `.env` file, set the value of `OTEL_EXPORTER_OTLP_HEADERS` to the OTLP
   Authorization Header obtained from the Last9 dashboard and make sure the
   value of the header is URL encoded.

```bash
OTEL_EXPORTER_OTLP_HEADERS="Authorization=<BASIC_AUTH_HEADER>"
```

5. Run the Roda application:

```bash
bundle exec rackup config.ru
```

6. Once the server is running, you can access the application at
   `http://localhost:9292` by default. The API endpoints are:

- GET `/hello/bob` - Hello user named bob

7. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces and metrics in action.

![Traces](./traces.png)
