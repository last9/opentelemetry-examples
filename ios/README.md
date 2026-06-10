# Last9 RUM — iOS Example

A runnable SwiftUI app demonstrating the [Last9 RUM iOS SDK](https://cdn.last9.io/rum-sdk/ios/builds/0.7.1/Last9RUM.podspec)
(`Last9RUM` v0.7.1). It exercises the full RUM feature surface: SDK
initialization, automatic view tracking via `NavigationStack`, automatic
`URLSession` network instrumentation, `identify`/`clearUser`, caught and
uncaught error capture, custom events, global span attributes, session id, and
flush.

## Prerequisites

- **Xcode 15+** (tested with Xcode 26.4), iOS 16.0+ simulator or device
  (the app uses SwiftUI `NavigationStack`, which requires iOS 16; the SDK
  itself supports iOS 15.1+)
- **XcodeGen** — `brew install xcodegen`
- **CocoaPods** — `sudo gem install cocoapods` (tested with 1.16.2)
- A **Last9 account** for the client token, base URL (with org path), and origin

## Quick Start

```bash
cd ios

# 1. Create your secrets file and fill in your Last9 values.
cp Secrets.example.xcconfig Secrets.xcconfig
# edit Secrets.xcconfig

# 2. Generate the Xcode project from project.yml.
xcodegen generate

# 3. Install the Last9 RUM pod (fetches the podspec from the Last9 CDN).
#    Defaults to v0.7.1; override with `export LAST9_RUM_VERSION=<version>`.
pod install

# 4. Open the generated workspace and Run (Cmd-R).
open RUMExample.xcworkspace
```

## Configuration

Secrets live in `Secrets.xcconfig` (git-ignored). They are surfaced into
`Info.plist` keys at build time and read at runtime via
`Bundle.main.object(forInfoDictionaryKey:)` (see `Sources/RUMConfig.swift`).

| xcconfig key         | Maps to                | Example value                                            |
|----------------------|------------------------|----------------------------------------------------------|
| `LAST9_BASE_URL`     | `L9RumConfig.baseUrl`  | `otlp-ext-aps1.last9.io/v1/otlp/organizations/your-org`  |
| `LAST9_CLIENT_TOKEN` | `L9RumConfig.clientToken` | `your-client-token`                                   |
| `LAST9_ORIGIN`       | `L9RumConfig.origin`   | `app.last9.io`                                           |

Non-secret values are hardcoded in `Sources/RUMExampleApp.swift`:
`serviceName = "rum-ios-example"`, `serviceVersion = "1.0.0"`,
`deploymentEnvironment = "development"`.

**SDK source.** The `Last9RUM` pod is fetched from the Last9 CDN podspec
`https://cdn.last9.io/rum-sdk/ios/builds/<version>/Last9RUM.podspec` (see the
`Podfile`). The version defaults to `0.7.1`; pin a different one with
`export LAST9_RUM_VERSION=<version>` before `pod install`.

`Config-Debug.xcconfig` / `Config-Release.xcconfig` (committed) are the base
configs set in `project.yml`. Each one `#include`s the CocoaPods-generated pod
config (so `Last9RUM` links) and your git-ignored `Secrets.xcconfig`. You only
ever edit `Secrets.xcconfig`.

### Note on URL values (the `//` problem)

xcconfig treats `//` as the start of a comment, so a value like
`https://otlp-ext-aps1.last9.io/...` is silently truncated to `https:`.
To avoid this, **store URLs without the `https://` scheme** (host + path only)
in `Secrets.xcconfig`. The app re-adds `https://` at runtime in
`RUMConfig.swift`. The placeholders in `Secrets.example.xcconfig` already follow
this convention.

## What the app does

Three screens reached by real `NavigationStack` route navigation (so view
tracking fires on each transition):

1. **Home** — `identify()` / `clearUser()`, `addEvent()`, `spanAttributes()`
   (set and clear), and navigation buttons.
2. **Network** — a GET (`/todos/1`) and a POST (`/posts`) to
   `https://jsonplaceholder.typicode.com` via `URLSession`. The response is
   shown in the UI.
3. **Errors** — a caught error routed through `captureError(_:context:)`, a
   button that raises an uncaught error to exercise automatic error
   instrumentation, the live `getSessionId()`, and a `flush()` button.

## Verification

With a real token configured, after running the app and tapping through the
screens you should see in your Last9 dashboard:

- A **session** for `rum-ios-example` (`development` environment)
- **Views** for the Home, Network, and Errors screens (one per navigation)
- **HTTP spans** for the GET and POST, each with DNS/TCP/TLS/TTFB phase child
  spans (under Sessions → APIs)
- An **error** event (the caught `captureError`, and the uncaught crash on next
  launch)
- The custom **event** `purchase_completed` and the global span attributes
- A `flush()` immediately pushes any buffered telemetry

See the [Last9 RUM docs](https://last9.io/docs/) for more detail.
