# Last9 RUM Custom Spans (React + Vite)

A minimal Vite + React + TypeScript app showing how to create custom OpenTelemetry spans with the
Last9 browser RUM SDK (v2). The SDK is loaded from the Last9 CDN script tag in `index.html` (it sets
`window.L9RUM`); `@opentelemetry/api` comes from npm.

> **Caution:** Pin `@opentelemetry/api` to `1.9.0`, the version the SDK bundles. A newer minor (for example 1.10.0) silently
> gets a no-op tracer, so custom spans are dropped with no error, even though exports still return 200.

Install it with `npm i @opentelemetry/api@1.9.0 --save-exact`.

Spans created:

- `react.app.mounted` - a component-mount span, guarded with a ref so StrictMode does not create it twice.
- `react.simple` - attributes and a ~200ms duration.
- `react.checkout` - a parent span with a nested `react.checkout.validate` child and a `fetch` call.
- `react.error` - a recorded exception and ERROR status.

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
3. Look for `react.app.mounted`, `react.simple`, `react.checkout` (with child `react.checkout.validate`), and `react.error`.

## Notes

- **Init once, outside components.** `src/rum.ts` calls `window.L9RUM.init()` at module level. Calling it from a
  `useEffect` would run it twice under `<StrictMode>` in development.
- **`init()` is async.** Spans started before its promise resolves are dropped, so each handler does
  `await rumReady` first. Rendering is not blocked on init.
- **Install `@opentelemetry/api` yourself.** `@last9/rum` is not published on npm, and relying on a transitive
  copy of `@opentelemetry/api` breaks under pnpm and Yarn PnP. A copy at the same version (1.9.0) finds the SDK's tracer provider
  through `Symbol.for("opentelemetry.js.api.1")`.
- **fetch nesting.** The SDK records the `fetch` as its own network span under the page view trace, not under
  `react.checkout`.
