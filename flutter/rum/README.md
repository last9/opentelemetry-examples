# Last9 RUM Flutter Example

A runnable Flutter app demonstrating the full feature surface of the
[Last9 RUM Flutter SDK](https://cdn.last9.io/rum-sdk/flutter/): session and
view tracking, automatic network instrumentation, error capture, user
identification, custom events, global span attributes, and flush.

Three real screens reached via named-route navigation (so automatic view
tracking fires on each navigation):

- **Home** — `identify()`, `clearUser()`, `addEvent()`, `spanAttributes()`, and navigation buttons.
- **Network** — a GET and a POST to `jsonplaceholder.typicode.com` (auto-instrumented).
- **Errors** — a caught error via `captureError()`, an uncaught error, plus `getSessionId()` and `flush()`.

## Prerequisites

- Flutter 3.41.6 (Dart 3.11.4) or compatible (`flutter >= 3.10.0`, Dart `>= 3.0.0`)
- Last9 RUM Flutter SDK **v0.7.1** (downloaded by `./download_sdk.sh`)
- A Last9 account for the client token, base URL, and origin
- For iOS: Xcode + CocoaPods. For Android: Android SDK.

## Quick Start

```bash
# 1. Download + checksum-verify + extract the SDK into git-ignored vendor/
#    Defaults to v0.7.1; override with `LAST9_RUM_VERSION=<version> ./download_sdk.sh`
#    (also `export LAST9_RUM_VERSION=<version>` so iOS `pod install` matches).
./download_sdk.sh

# 2. Resolve Dart dependencies (needs vendor/flutter to exist)
flutter pub get

# 3. iOS only: install the native pod (Last9RUM via CDN podspec)
cd ios && pod install && cd ..

# 4. Provide your token (this file is git-ignored)
cp last9.env.example.json last9.env.json
# edit last9.env.json and fill in your real values

# 5. Run
flutter run --dart-define-from-file=last9.env.json
```

> **SDK source (Last9 CDN).** The Dart SDK is a path dependency on the vendored
> `vendor/flutter`, downloaded by `download_sdk.sh` from
> `https://cdn.last9.io/rum-sdk/flutter/builds/<version>/`. The native deps
> resolve from the CDN too: Android via the Maven repo in
> `android/settings.gradle.kts`, iOS via the podspec in `ios/Podfile`. The
> version defaults to `0.7.1`; set `LAST9_RUM_VERSION` to change all three.

## Configuration

Secret values are injected at build time from `last9.env.json` via
`--dart-define-from-file` and read with `String.fromEnvironment`. Non-secret
values are hardcoded in `lib/main.dart`.

| Source | Key / constant | Maps to | Example |
|--------|----------------|---------|---------|
| `last9.env.json` | `LAST9_BASE_URL` | `baseUrl` | `https://otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>` |
| `last9.env.json` | `LAST9_CLIENT_TOKEN` | `clientToken` | `your-client-token` |
| `last9.env.json` | `LAST9_ORIGIN` | `origin` | `https://app.last9.io` |
| source | `serviceName` | `service.name` | `rum-flutter-example` |
| source | `serviceVersion` | `service.version` | `1.0.0` |
| source | `deploymentEnvironment` | `deployment.environment` | `development` |

## Verification

After running with a real token and tapping through the screens, you should
see in the Last9 dashboard:

- A **session** for the app launch.
- A **view span per screen** (Home, Network, Errors) as you navigate.
- **HTTP spans** for the GET and POST on the Network screen, with
  DNS/TCP/TLS/TTFB phase child spans.
- An **error** from the Errors screen — both the caught `captureError()` call
  (with `screen`/`kind` context) and the uncaught thrown exception.
- The **session ID** shown on the Errors screen matches the dashboard session.

See the [Last9 docs](https://docs.last9.io) for dashboard details.
