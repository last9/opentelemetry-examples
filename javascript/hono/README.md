# Auto instrumenting Hono application with OpenTelemetry

This example demonstrates how to auto-instrument a Hono application with
OpenTelemetry. Make sure you have **Node.js v18** or higher installed on your
machine.

## Setup and running the example

1. To clone this example run the following command:

```bash
npx degit last9/opentelemetry-examples/javascript/hono hono
```
2. Obtain the OTLP endpoint and the Auth Header from the Last9 dashboard and
   modify the values of the `OTLP_ENDPOINT` and `OTLP_AUTH_HEADER` variables.

   Update these values in the `otelSetup.js` file.

   Also set appropriate `service name` in the `otelSetup.js` file.

3. Next, install the dependencies by running the following command in the
   `hono` directory:

```bash
npm install
```

4. To build the project, run the following command in the `hono` directory:

```bash
bun run app.js
```

Once the server is running, you can access the application at
`http://localhost:3000` by default. Where you can make CRUD operations. The API
endpoints are:

- POST `/tasks` - Create a new task
- GET `/tasks` - Get all tasks
- PUT `/tasks/:id` - Update a task
- DELETE `/tasks/:id` - Delete a task

5. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces in action.

## How does it work?

There are two files that are important to this example:

1. `otelSetup.js` - This file is responsible for setting up the OpenTelemetry SDK and configuring the exporter.
2. `otelMiddleware.js` - This file is responsible for adding the middleware to the Hono application.

The `otelSetup.js` file initializes the OpenTelemetry SDK and sets up the exporter to send the data to the Last9.

The `otelMiddleware.js` file is responsible for creating a span for each incoming request and adding the necessary attributes to the span. It also adds the span to the context so that it can be used in the rest of the application.

You need to make sure that the `otelSetup.js` file is called before any other middleware or route handler in the application.

Also, sure that otelMiddleware is added as a middleware to the Hono application for every route you want to trace.

```javascript
import { Hono } from 'hono';
import { setupOTel } from './otelSetup.js';
import { otelMiddleware } from './otelMiddleware.js';

setupOTel();

const app = new Hono();
app.use("*", otelMiddleware());
```

> The otelMiddleware generates OpenTelemetry spans for every incoming request. It uses a function `normalizePath` to normalize the path of the request. This is done to avoid high cardinality span names. The original route is retained in the `http.route` attribute.