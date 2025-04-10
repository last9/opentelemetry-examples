# Auto instrumenting Fastify application with OpenTelemetry

This example demonstrates how to auto-instrument a Fastify application with
OpenTelemetry. Make sure you have **Node.js v20** or higher installed on your
machine.

1. To clone this example run the following command:

```bash
npx degit last9/opentelemetry-examples/javascript/fastify fastify
```

2. Create a `.env` file in the root directory and add the following environment variables:

```bash
PORT=3000
OTEL_EXPORTER_OTLP_ENDPOINT=your_last9_otlp_endpoint
OTEL_EXPORTER_OTLP_HEADERS=your_last9_auth_header
```

3. Obtain the OTLP endpoint and the Auth Header from the Last9 dashboard and
   modify the values of the `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` variables
   accordingly in the `.env` file.

4. Install the dependencies by running the following command:

```bash
npm install
```

5. Start the server in development mode:

```bash
npm run dev
```

Or start in production mode:

```bash
npm run start
```

Once the server is running, you can access the application at
`http://localhost:3000` by default. The API endpoints are:

- GET `/` - Welcome message
- GET `/api/users` - Get all users
- GET `/api/users/:id` - Get user by ID
- POST `/api/users/create` - Create a user
- PUT `/api/users/update/:id` - Update a user
- DELETE `/api/users/delete/:id` - Delete a user

6. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the [Trace Explorer](https://app.last9.io/traces)

## Project Structure

- `src/server.js` - Main Fastify server setup with OpenTelemetry initialization
- `src/instrumentation.js` - OpenTelemetry configuration and setup
- `src/routes/` - API route handlers
- `.env` - Environment variables configuration

## Dependencies

- `@fastify/otel` - OpenTelemetry plugin for Fastify
- `@opentelemetry/auto-instrumentations-node` - Auto-instrumentation for Node.js
- `@opentelemetry/exporter-trace-otlp-http` - OTLP HTTP exporter for traces
- `@opentelemetry/resources` - OpenTelemetry resource definitions
- `@opentelemetry/sdk-node` - OpenTelemetry Node.js SDK
- `@opentelemetry/semantic-conventions` - Standard semantic conventions
- `axios` - HTTP client for making requests
- `dotenv` - Environment variable loader
- `fastify` - Fast web framework for Node.js