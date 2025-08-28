# @opentelemetry/instrumentation-polka

OpenTelemetry instrumentation for the [Polka](https://github.com/lukeed/polka) web framework.

## Features
- Automatically creates spans for each HTTP request handled by Polka
- Span names use the HTTP method and matched route pattern (e.g., `GET /users/:id`)
- Sets `http.route`, `http.method`, and `http.target` attributes

## Installation

```
# In your project root
npm install ./src/polka-instrumentation
```

## Usage (with OpenTelemetry SDK auto-instrumentation)

```js
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { PolkaInstrumentation } = require('@opentelemetry/instrumentation-polka');

const sdk = new NodeSDK({
  instrumentations: [
    getNodeAutoInstrumentations(),
    new PolkaInstrumentation(),
  ],
  // ... other options ...
});

sdk.start();
```

## Usage in your Polka app

```js
const polka = require('polka');
const { PolkaInstrumentation } = require('@opentelemetry/instrumentation-polka');

const app = polka();
// ... define routes ...

// Patch the app instance for instrumentation
const polkaInstrumentation = new PolkaInstrumentation();
polkaInstrumentation.patchApp(app);

app.listen(3000);
```

## How it works
- Patches the Polka app's handler to start a span for each request
- Uses Polka's internal route matching to determine the route pattern
- Ends the span when the response finishes 