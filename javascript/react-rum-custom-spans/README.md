# Last9 RUM Custom Spans (React + Vite)

A minimal Vite + React + TypeScript app showing how to create custom spans with the Last9 browser RUM SDK
(v2.14.0+). The SDK is loaded from the Last9 CDN script tag in `index.html` (it sets `window.L9RUM`).
There is no `@opentelemetry/api` dependency.

Spans and errors created:

- `react.app.mounted` - `recordSpan` with `startTimeMs` / `endTimeMs` for a component mount, guarded with a ref so StrictMode does not create it twice.
- `react.recorded` - `recordSpan` with `durationMs: 200` and attributes.
- `react.checkout` - `startSpan` / `endSpan` around a `fetch` call.
- A handled error - `captureError(error, attributes)`, shown in Error Tracking.

## Prerequisites

- Your org's RUM endpoint and a RUM client token: copy both from the [RUM integration page](https://app.last9.io/integrations?integration=RUM) in Last9
- The token's allowed origins must include `http://localhost:3001`
- Node.js 18+

## Quick Start

```bash
cd javascript/react-rum-custom-spans

# 1. Create your git-ignored env file and fill in your values
cp .env.example .env.local

# 2. Install and run
npm install
npm run dev

# 3. Open http://localhost:3001 and click the buttons
```

If the browser loads a cached SDK older than v2.14.0, the status line asks you to hard-refresh and the span buttons stay disabled.

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_L9_BASE_URL` | Your org's RUM endpoint, copied from the RUM integration page | `<your-org-rum-endpoint>` |
| `VITE_L9_CLIENT_TOKEN` | RUM client token | `<your-rum-client-token>` |
| `VITE_L9_SERVICE_NAME` | Service name shown in Last9 | `react-rum-custom-spans` |
| `VITE_L9_ENV` | Environment label | `local` |

## Verify in Last9

1. Open **Traces** in Last9.
2. Filter by service `react-rum-custom-spans`.
3. Look for `react.app.mounted`, `react.recorded` and `react.checkout`, under the page's `View` span.

## How to add this to your app

1. Load the SDK in `index.html` before your app bundle:

   ```html
   <script src="https://cdn.last9.io/rum-sdk/builds/stable/v2/l9.umd.js"></script>
   ```

2. Copy [`src/l9rum.d.ts`](src/l9rum.d.ts) so TypeScript knows `window.L9RUM`.
3. Initialize once at module level, as in [`src/rum.ts`](src/rum.ts), and export the promise.
4. `await rumReady` before you call `recordSpan`, `startSpan` or `endSpan`.
5. Check `customSpansSupported` (also in `src/rum.ts`) before calling them, so a cached pre-2.14.0 SDK shows a recovery message instead of throwing.

## Notes

- **Init once, outside components.** `src/rum.ts` calls `window.L9RUM.init()` at module level, so rendering is not blocked on it.
- **`init()` is async.** Custom span calls made before its promise resolves return `false` / `null` and emit nothing, so each handler does `await rumReady` first.
- **Parenting.** Custom spans are children of the current page view and carry `view.id` and `l9.span.category=custom`. The SDK records the `fetch` as its own network span under the same view, not under `react.checkout`.
- **Do not create spans with your own `@opentelemetry/api`.** An app copy with a newer minor version than the SDK's bundled 1.9.0 gets a silent no-op tracer. Use the `L9RUM` methods instead.

See [Custom Spans](https://last9.io/docs/real-user-monitoring/web/#custom-spans) in the Web RUM SDK docs.
