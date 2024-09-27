# Auto instrumenting Koa application with OpenTelemetry

This example demonstrates how to auto-instrument a [Koa](https://koajs.com/) application with
OpenTelemetry. Make sure you have **Node.js v18** or higher installed on your
machine.

## Prerequisites

- Node.js v18 or higher
- Last9 account
- Koa application

## Getting started

Check the [src/instrumentation.ts](./src/instrumentation.ts) file to see how the tracer is configured. 

Make sure you require the `src/instrumentation.ts` file in your entry point before `koa` is imported.

```typescript
import { setupTracing } from "./instrumentation";
// Do this before requiring koa package
setupTracing("koa-api-server");
import Koa from 'koa';
```

## Running the example

1. To clone this example run the following command:

```bash
npx degit last9/opentelemetry-examples/javascript/koa koa
```

2. Create `.env` file and add the contents of
   `.env.example` file.

   ```bash
   cd env
   cp .env.example .env
   ```

3. Obtain the OTLP endpoint and the Auth Header from the Last9 dashboard and
   modify the values of the `OTLP_ENDPOINT` and `OTLP_AUTH_HEADER` variables
   accordingly in the `.env` file.

4. Next, install the dependencies by running the following command in the
   `koa` directory:

```bash
npm install
```

5. To start the project, run the following command in the `koa` directory:

```bash
npm run dev
```

Once the server is running, you can access the application at
`http://localhost:3000` by default. Where you can make CRUD operations. 

The API endpoints are:

- POST `/api/users/add` - Create a new user
- GET `/api/users/all` - Get all users
- PUT `/api/users/update` - Update a user
- DELETE `/api/users/delete/:id` - Delete a user

7. Sign in to [Last9 Dashboard](https://app.last9.io) and visit the APM
   dashboard to see the traces in action.

## Troubleshooting

If you want to debug the tracer, uncomment the following line in the [src/instrumentation.ts](./src/instrumentation.ts) file:

```typescript
// import { diag, DiagConsoleLogger, DiagLogLevel } from "@opentelemetry/api";
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);
```

And run the project again. You should see the debug logs in the console.
