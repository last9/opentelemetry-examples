Use OpenTelemetry to instrument your Angular application and send telemetry data
to Last9. You can either run OpenTelemetry Collector or send the telemetry
directly from the application. Read the
[setup guide](https://docs.last9.io/docs/integrations-opentelemetry-angular)
for more details.

### Instrumentation packages

Install the following packages:

```sh
npm install \
  @opentelemetry/api@1.9.0 \
  @opentelemetry/auto-instrumentations-web@0.48.1 \
  @opentelemetry/exporter-trace-otlp-http@0.48.0 \
  @opentelemetry/instrumentation@0.48.0 \
  @opentelemetry/resources@1.30.1 \
  @opentelemetry/sdk-trace-web@1.30.1 \
  @opentelemetry/semantic-conventions@1.34.0
```

### Setup auto-instrumentation using OpenTelemetry

#### Environment variables

Set the environment variables in your Angular environment files:

**src/environments/environment.ts** (for development):
```typescript
export const environment = {
  production: false,
  environment: 'Dev',
  serviceVersion: '1.0.0',
  last9: {
    traceEndpoint: 'YOUR_LAST9_OTLP_ENDPOINT_HERE',
    authorizationHeader: 'YOUR_LAST9_TOKEN_HERE',
    serviceName: 'your-service-name'
  }
};
```

**src/environments/environment.prod.ts** (for production):
```typescript
export const environment = {
  production: true,
  environment: 'Prod',
  serviceVersion: '1.0.0',
  last9: {
    traceEndpoint: 'YOUR_LAST9_OTLP_ENDPOINT_HERE',
    authorizationHeader: 'YOUR_LAST9_TOKEN_HERE',
    serviceName: 'your-service-name'
  }
};
```

#### TypeScript

Create a file named `instrumentation.ts` and add the following code:

```ts
import {
  WebTracerProvider,
  ConsoleSpanExporter,
  SimpleSpanProcessor,
  BatchSpanProcessor,
} from "@opentelemetry/sdk-trace-web";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { getWebAutoInstrumentations } from "@opentelemetry/auto-instrumentations-web";
import { Resource } from "@opentelemetry/resources";
import { SemanticResourceAttributes } from "@opentelemetry/semantic-conventions";

import { environment } from '../environments/environment';

// Environment variables (browser equivalent of process.env)
const OTEL_SERVICE_NAME = environment.last9?.serviceName;
const OTEL_EXPORTER_OTLP_ENDPOINT = environment.last9?.traceEndpoint;
const OTEL_EXPORTER_OTLP_HEADERS = environment.last9?.authorizationHeader;
const OTEL_RESOURCE_ATTRIBUTES = environment.environment;
const SERVICE_VERSION = environment.serviceVersion;

// Validate required environment variables
if (!OTEL_SERVICE_NAME) {
  throw new Error('OTEL_SERVICE_NAME is required. Please set environment.last9.serviceName');
}
if (!OTEL_EXPORTER_OTLP_ENDPOINT) {
  throw new Error('OTEL_EXPORTER_OTLP_ENDPOINT is required. Please set environment.last9.traceEndpoint');
}
if (!OTEL_EXPORTER_OTLP_HEADERS) {
  throw new Error('OTEL_EXPORTER_OTLP_HEADERS is required. Please set environment.last9.authorizationHeader');
}

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: OTEL_SERVICE_NAME,
  [SemanticResourceAttributes.SERVICE_VERSION]: SERVICE_VERSION || '1.0.0',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: OTEL_RESOURCE_ATTRIBUTES || 'development',
});

const provider = new WebTracerProvider({ resource });

// Add console exporter for debugging (optional)
provider.addSpanProcessor(new SimpleSpanProcessor(new ConsoleSpanExporter()));

// Configure the OTLP exporter
const otlp = new OTLPTraceExporter({
  url: OTEL_EXPORTER_OTLP_ENDPOINT,
  headers: {
    Authorization: OTEL_EXPORTER_OTLP_HEADERS,
  },
});

provider.addSpanProcessor(new BatchSpanProcessor(otlp));

provider.register();

// Automatically instrument the Angular application
registerInstrumentations({
  instrumentations: [
    getWebAutoInstrumentations({
      // Enable specific instrumentations for Angular
      "@opentelemetry/instrumentation-document-load": {
        enabled: true,
      },
      "@opentelemetry/instrumentation-user-interaction": {
        enabled: true,
      },
      "@opentelemetry/instrumentation-fetch": {
        propagateTraceHeaderCorsUrls: /.+/,
      },
      "@opentelemetry/instrumentation-xml-http-request": {
        propagateTraceHeaderCorsUrls: /.+/,
      },
    }),
  ],
});
```

This script must be imported at the application's entry point. In your `src/main.ts` file, import it at the top:

```ts
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';
import './app/instrumentation'; // Import instrumentation first

bootstrapApplication(App, appConfig)
  .catch((err) => console.error(err));
```

#### JavaScript

Create a file named `instrumentation.js` and add the following code:

```js
// instrumentation.js
const opentelemetry = require('@opentelemetry/sdk-trace-web');
const { getWebAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-web');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// Configuration - Replace with your actual values
const LAST9_ENDPOINT = "YOUR_LAST9_OTLP_ENDPOINT_HERE";
const LAST9_AUTH = "YOUR_LAST9_TOKEN_HERE"; 
const SERVICE_NAME = "your-service-name"; // Replace with your service name
const SERVICE_VERSION = "1.0.0";
const ENVIRONMENT = "development";

// Simple logging utility
const logger = {
  info: (message) => console.log(`[OpenTelemetry] ${message}`),
  error: (message, error) => console.error(`[OpenTelemetry Error] ${message}`, error || '')
};

logger.info(`Initializing OpenTelemetry for service: ${SERVICE_NAME}`);

// Create and configure provider
const provider = new opentelemetry.WebTracerProvider({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: SERVICE_NAME,
    [SemanticResourceAttributes.SERVICE_VERSION]: SERVICE_VERSION,
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: ENVIRONMENT,
  }),
});

// Configure the OTLP exporter
const otlp = new OTLPTraceExporter({
  url: LAST9_ENDPOINT,
  headers: {
    Authorization: LAST9_AUTH,
  },
});

provider.addSpanProcessor(new opentelemetry.BatchSpanProcessor(otlp));
provider.register();

// Initialize instrumentations
const { registerInstrumentations } = require('@opentelemetry/instrumentation');

registerInstrumentations({
  instrumentations: [
    getWebAutoInstrumentations({
      '@opentelemetry/instrumentation-document-load': { enabled: true },
      '@opentelemetry/instrumentation-user-interaction': { enabled: true },
      '@opentelemetry/instrumentation-fetch': {
        propagateTraceHeaderCorsUrls: /.+/,
      },
      '@opentelemetry/instrumentation-xml-http-request': {
        propagateTraceHeaderCorsUrls: /.+/,
      },
    }),
  ],
});

logger.info('OpenTelemetry instrumentation setup complete');
```

This script must be imported at the application's entry point. In your `src/main.js` file, import it at the top:

```js
import './app/instrumentation'; // Import instrumentation first
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';

bootstrapApplication(App, appConfig)
  .catch((err) => console.error(err));
```

---

The above code performs the following steps:

1. Set up Trace Provider with the application's name as Service Name.
2. Set up OTLP Exporter with Last9 OTLP endpoint.
3. Set up auto instrumentation.

Once you run the Angular application, it will start sending telemetry data to Last9.