# Last9 RUM Custom Spans (Browser)

A no-build browser page showing how to create custom spans with the Last9 browser RUM SDK (v2.14.0+).
The SDK is loaded from the Last9 CDN, so there is nothing to install and no `@opentelemetry/api` dependency.

Three buttons:

- **Recorded span** - `L9RUM.recordSpan("demo.recorded", { durationMs: 200, attributes })`: one finished span.
- **Timed span + fetch** - `L9RUM.startSpan("demo.checkout")` ... `L9RUM.endSpan(handle)` around a `fetch` call. The SDK records the `fetch` as its own network span (`GET /delay/?`) under the same page view, next to `demo.checkout`.
- **Handled error** - `L9RUM.captureError(error, attributes)`: a handled error in Error Tracking.

Custom spans are children of the current page view and carry `view.id` and `l9.span.category=custom`.

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

The status line shows the result of `L9RUM.sendTestEvent()`, so you know telemetry reaches Last9 before you click anything.

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
3. Look for the span names `demo.recorded` and `demo.checkout`, and the `View` span they belong to.

## Custom span API

```js
// A finished span: ends now, started 250 ms ago
L9RUM.recordSpan("checkout.validate", { durationMs: 250, attributes: { items: 3 } });

// Or with explicit epoch-ms times
L9RUM.recordSpan("sync", { startTimeMs: t0, endTimeMs: t1, kind: "client" });

// A span you end yourself
const handle = L9RUM.startSpan("upload", { attributes: { "file.type": "png" } });
// ... later
L9RUM.endSpan(handle);
```

- Call these after `await L9RUM.init(...)`. Before init, or in a session that is not sampled, they log a warning and return `false` / `null`.
- `kind` is `"internal"` (default), `"client"`, `"server"`, `"producer"` or `"consumer"`.
- Attributes keep strings, booleans, finite numbers and string arrays; other values are dropped.
- A span not ended within 5 minutes, or still open on page exit, is ended with ERROR status.

See [Custom Spans](https://last9.io/docs/real-user-monitoring/web/#custom-spans) in the Web RUM SDK docs.

## Using a bundler (React, Vite, etc.)

`@last9/rum` is not published on npm. Load the SDK from the CDN script tag in your `index.html` (it sets
`window.L9RUM`) and call the same methods. No `@opentelemetry/api` install is needed. See
[`../react-rum-custom-spans`](../react-rum-custom-spans) for a complete Vite + React + TypeScript example.

> **Do not create spans with your own `@opentelemetry/api`.** The SDK bundles `@opentelemetry/api` 1.9.0, and an app
> copy with a newer minor version (for example 1.10.0) gets a silent no-op tracer: no custom spans, while exports
> still return 200. Use the `L9RUM` methods instead.

## Troubleshooting

- **Status says the SDK is older than v2.14.0**: your browser has an older cached copy of the stable script. Hard-refresh the page.
- **`recordSpan` returns `false`**: it was called before `init` resolved, the session is not sampled (this example uses `sampleRate: 100`), or the options are invalid (both `durationMs` and `startTimeMs`/`endTimeMs`, a negative duration, or `end < start`).
