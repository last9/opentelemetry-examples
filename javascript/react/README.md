# Auto instrumenting React application with OpenTelemetry

This example demonstrates how to auto-instrument an React application with
OpenTelemetry. Make sure you have **Docker** & **Node.js v18** or higher
installed on your machine.

1. Clone this project

```bash
npx degit last9/opentelemetry-examples/javascript/react with-react
```

2. Change directory to the project folder and install the dependencies

```bash
cd with-react
npm install
```

3. Update the config in otelcol-config.yaml file by adding the Authorization
   header. You can obtain the values from the Last9 dashboard.

```yaml
exporters:
  otlp:
    endpoint: "otlp.last9.io:443"
    headers:
      Authorization: "<BASIC_AUTH_HEADER>"
```

4. Next, Start the OpenTelemetry collector using the following command:

```bash
docker-compose up -d --build
```

This will expose the OTLP endpoint at `localhost:4317` which will be used by
frontend application to send traces.

3. Create `.env.local` file and add the following environment variable.

```env
VITE_OTLP_ENDPOINT=http://localhost:4317/v1/traces
```

4. Start the React application using the following command:

```bash
npm run dev
```

You can now interact with the React application at `http://localhost:5173` and
the traces will be sent to Last9 via a local OpenTelemetry collector.

6. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces in action.
