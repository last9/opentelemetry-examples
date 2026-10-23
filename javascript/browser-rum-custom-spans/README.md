# Last9 RUM Custom Spans (Browser)

A no-build browser page showing how to create custom OpenTelemetry spans with the
Last9 browser RUM SDK (v2).
The SDK is loaded from the Last9 CDN and `@opentelemetry/api` from jsDelivr, so there is nothing to install.

Three buttons create spans:

- **Simple span** - `demo.simple`, with attributes and a ~200ms duration.
- **Parent span + fetch** - `demo.checkout` with a nested `demo.checkout.validate` child and a `fetch` call. The SDK records the `fetch` as its own network span (`GET /delay/?`) under the page view trace, not under `demo.checkout`.
- **Error span** - `demo.error`, with a recorded exception and ERROR status.

The SDK registers its tracer provider globally, and an `@opentelemetry/api` copy at the same version (1.9.0) finds it through
`Symbol.for("opentelemetry.js.api.1")`. Spans from `trace.getTracer(...)` therefore go out through the SDK's exporter.

## Prerequisites

- Your org's RUM endpoint and a RUM client token: copy both from the [RUM integration page](https://app.last9.io/integrations?integration=RUM) in Last9
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
| `baseUrl` | Your org's RUM endpoint, copied from the RUM integration page | `<your-org-rum-endpoint>` |
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
      baseUrl: '<your-org-rum-endpoint>',
      headers: { clientToken: '<your-rum-client-token>' },
      resourceAttributes: { serviceName: 'your-app-name', deploymentEnvironment: 'production' }
    });
  });
</script>
```

Deferred and module scripts run in document order, so keep the SDK `<script>` tag first.

## Using a bundler (React, Vite, etc.)

> **Caution:** Pin `@opentelemetry/api` to `1.9.0`, the version the SDK bundles. A newer minor (for example 1.10.0) silently
> gets a no-op tracer, so custom spans are dropped with no error, even though exports still return 200.

`@last9/rum` is not published on npm. Keep loading the SDK from the CDN script tag in your `index.html`
(it sets `window.L9RUM`), and install `@opentelemetry/api` yourself to create custom spans:

```bash
npm i @opentelemetry/api@1.9.0 --save-exact
```

Install it directly rather than relying on a transitive dependency, because pnpm and Yarn PnP block access
to undeclared dependencies.

```js
import { trace } from "@opentelemetry/api";

await window.L9RUM.init({ /* same options as above */ });

const tracer = trace.getTracer("my-app");
const span = tracer.startSpan("my.operation");
span.end();
```

Spans created before `L9RUM.init()` resolves are no-ops, so `await` it first. See
[`../react-rum-custom-spans`](../react-rum-custom-spans) for a complete Vite + React example.
