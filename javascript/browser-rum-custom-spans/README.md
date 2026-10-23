# Last9 RUM Custom Spans (Browser)

A no-build browser page showing how to create custom OpenTelemetry spans with the
[Last9 browser RUM SDK](https://www.npmjs.com/package/@last9/rum) (`@last9/rum`, v2).
The SDK is loaded from the Last9 CDN and `@opentelemetry/api` from jsDelivr, so there is nothing to install.

Three buttons create spans:

- **Simple span** - `demo.simple`, with attributes and a ~200ms duration.
- **Parent span + fetch** - `demo.checkout` with a nested `demo.checkout.validate` child and a `fetch` call. The SDK records the `fetch` as its own network span (`GET /delay/?`) under the page view trace, not under `demo.checkout`.
- **Error span** - `demo.error`, with a recorded exception and ERROR status.

The SDK registers its tracer provider globally, and any `@opentelemetry/api` 1.x copy finds it through
`Symbol.for("opentelemetry.js.api.1")`. Spans from `trace.getTracer(...)` therefore go out through the SDK's exporter.

## Prerequisites

- A Last9 RUM client token from the [RUM integration page](https://app.last9.io/integrations?integration=RUM)
- The token's allowed origins must include `http://localhost:3000`
- Node.js (only for `npx serve`; any static file server works)

## Quick Start

```bash
cd javascript/browser-rum-custom-spans

# 1. Create your git-ignored config and fill in your values
cp config.example.js config.js

# 2. Serve the folder
npx serve -l 3000 .

# 3. Open http://localhost:3000 and click the buttons
```

## Configuration

`config.js` sets `window.L9_CONFIG`:

| Key | Description | Example |
|-----|-------------|---------|
| `baseUrl` | Last9 RUM OTLP endpoint | `https://otlp-ext-<region>.last9.io/v1/otlp/organizations/<your-org-slug>` |
| `clientToken` | RUM client token | `<your-rum-client-token>` |
| `serviceName` | Service name shown in Last9 | `browser-rum-custom-spans` |
| `deploymentEnvironment` | Environment label | `local` |

## Verify in Last9

1. Open **Traces** in Last9.
2. Filter by service `browser-rum-custom-spans`.
3. Look for the span names `demo.simple`, `demo.checkout` (with child `demo.checkout.validate`), and `demo.error`.

## Standard CDN setup

This example calls `L9RUM.init()` inside a module script so it can run before creating spans. The standard
snippet from the Last9 RUM integration page uses `defer` and a `load` listener:

```html
<script defer src="https://cdn.last9.io/rum-sdk/builds/stable/v2/l9.umd.js"></script>
<script>
  window.addEventListener('load', () => {
    L9RUM.init({
      baseUrl: 'https://otlp-ext-<region>.last9.io/v1/otlp/organizations/<your-org-slug>',
      headers: { clientToken: '<your-rum-client-token>' },
      resourceAttributes: { serviceName: 'your-app-name', deploymentEnvironment: 'production' }
    });
  });
</script>
```

Deferred and module scripts run in document order, so keep the SDK `<script>` tag first.

## Using npm instead of CDN

```bash
npm i @last9/rum @opentelemetry/api
```

Install `@opentelemetry/api` yourself rather than relying on it as a transitive dependency, because pnpm and
Yarn PnP block access to undeclared dependencies.

```js
import L9RUM from "@last9/rum";
import { trace, SpanStatusCode } from "@opentelemetry/api";

await L9RUM.init({ /* same options as above */ });

const tracer = trace.getTracer("my-app");
const span = tracer.startSpan("my.operation");
span.end();
```

Spans created before `L9RUM.init()` resolves are no-ops, so `await` it first.
