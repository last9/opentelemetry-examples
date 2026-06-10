# Last9 RUM — React Native (Expo) Example

A runnable Expo app demonstrating the full surface of the
[Last9 RUM React Native SDK](https://cdn.last9.io/rum-sdk/react-native/): SDK
initialization, automatic view tracking via React Navigation, network
instrumentation with W3C trace context and baggage, WebView session/view
correlation, user identity, caught/uncaught error capture, ANR detection,
custom events, global span attributes, session ID, and flush.

A bottom-tab navigator (`@react-navigation/bottom-tabs`) with 5 tabs, all
reached by real route navigation so automatic view tracking fires on every
navigation:

- **Home** 🏠 — a native-stack (`Dashboard` → `Detail`). Dashboard starts a
  `startView("Home")`, runs fast + delayed (`httpbin.org/delay`) GETs to drive
  `view.ttfd`, and renders posts; tapping a post navigates to Detail
  (post + comments).
- **Network** 🌐 — todos CRUD (GET list, POST create, PATCH toggle, DELETE)
  against `jsonplaceholder.typicode.com`, plus "Run Public API Demo" and
  "Run Tracked Requests Demo" and a scrolling API Log.
- **WebView** 🔗 — `react-native-webview` loading `https://app.last9.io/` with
  `getWebViewInjectedJavaScript()` native context plus a Browser-RUM bootstrap,
  and a native-context probe panel.
- **Errors** ⚠️ — 7 buttons: `captureError()` variants, TypeError, network
  error, promise rejection, deep stack trace, ANR simulation, and a 5-error
  burst.
- **Profile** 👤 — `identify()` / `clearUser()`, `spanAttributes()` set/clear,
  custom events (`addEvent()`), `setViewName()` / `flush()`, session info, an
  Active SDK Config card, and a debug Event Log modal (the global event log).

## Prerequisites

- Node.js >= 20
- A Last9 client token, base URL (with org path), and origin
- iOS: Xcode + CocoaPods
- Android: JDK + Android SDK

> A **development build** is required — the Last9 RUM SDK ships native modules,
> so it cannot run in Expo Go. `expo-dev-client` is included and the run steps
> below build a dev client for you.

## Quick Start

```bash
# 1. Install JS dependencies (also installs the SDK from the CDN tarball
#    declared in package.json).
npm install

# 2. Provide your token.
cp .env.example .env
# edit .env and fill in:
#   EXPO_PUBLIC_LAST9_BASE_URL
#   EXPO_PUBLIC_LAST9_CLIENT_TOKEN
#   EXPO_PUBLIC_LAST9_ORIGIN

# 3. Generate the native projects. The config plugin in
#    plugins/withLast9Rum.js injects the Last9 native deps:
#    the Maven repo into android/build.gradle and the Last9RUM
#    podspec into ios/Podfile.
npx expo prebuild

# 4. Run a development build.
npx expo run:android   # Android emulator/device
npx expo run:ios       # iOS simulator
```

Expo automatically loads `.env` and inlines the `EXPO_PUBLIC_*` variables into
`process.env`, which `src/rum.ts` reads. No extra dotenv plugin needed.

**Native deps are reproducible.** Expo regenerates `android/` and `ios/` on
every `expo prebuild`, so they are git-ignored. The
[`plugins/withLast9Rum.js`](./plugins/withLast9Rum.js) config plugin re-applies
the Last9 CDN Maven repo (Android) and `Last9RUM` podspec (iOS) on each prebuild
so the native wiring is never lost.

**SDK source.** The `@last9/rum-react-native` package is pinned in
`package.json` to the CDN tarball
`https://cdn.last9.io/rum-sdk/react-native/builds/<version>/last9-rum-react-native-<version>.tgz`
(currently `0.7.1`). To change the version, edit that dependency and re-run
`npm install`; keep the iOS podspec version in `plugins/withLast9Rum.js` in
sync, then re-run `npx expo prebuild --clean`.

## Configuration

Secrets come from a git-ignored `.env` file (auto-loaded by Expo as
`EXPO_PUBLIC_*` variables). The full `RUM_CONFIG` lives in `src/rum.ts`;
non-secret identity values are hardcoded there.

| Variable                          | Source         | Description                                              |
|-----------------------------------|----------------|----------------------------------------------------------|
| `EXPO_PUBLIC_LAST9_BASE_URL`      | `.env`         | OTLP collector endpoint (contains your org path)         |
| `EXPO_PUBLIC_LAST9_CLIENT_TOKEN`  | `.env`         | Authentication token from the Last9 dashboard            |
| `EXPO_PUBLIC_LAST9_ORIGIN`        | `.env`         | `X-LAST9-ORIGIN` header (required for client_monitoring)  |
| `serviceName`                     | `src/rum.ts`   | `rum-react-native-example`                               |
| `serviceVersion`                  | `src/rum.ts`   | `1.0.0`                                                  |
| `deploymentEnvironment`           | `src/rum.ts`   | `development`                                            |

`RUM_CONFIG` is defined in `src/rum.ts` and `L9Rum.initialize(RUM_CONFIG)` is
called at `App.tsx` module load — before any React `useEffect` fires — so
startup, errors, and network requests are captured from the first frame.

## Verification

After running with a real token, in the Last9 dashboard you should see:

- A **session** for the app launch (`getSessionId()` is shown on the Profile
  tab for cross-reference).
- A **view** per screen as you switch tabs and navigate Dashboard → Detail.
- **HTTP spans** (with DNS/TCP/TLS/TTFB phase child spans) from the Home TTFD
  requests and the todos CRUD / demo requests on the Network tab. Filter by the
  `l9_demo_tab` / `l9_demo_request` query tags.
- **WebView correlation** — the native `session.id` / `native.view.id` shared
  with Browser RUM in the loaded page (shown in the WebView tab probe panel).
- **Error** events from the 7 buttons on the Errors tab (`captureError`,
  TypeError, network error, promise rejection, deep stack, ANR sim, burst).
- Custom **events** (`button_click`, `feature_used`) and global span attributes
  (`app.experiment`, `app.feature_flag`) from the Profile tab.

See the [Last9 docs](https://last9.io/docs/) for dashboard details.
