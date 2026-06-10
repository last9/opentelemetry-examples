# Last9 RUM Android Example

A runnable Jetpack Compose app demonstrating the [Last9 RUM Android SDK](https://cdn.last9.io/rum-sdk/android/maven/) (`io.last9:rum-android:0.7.1`). It covers the full RUM feature surface: SDK init, automatic view tracking via Navigation Compose, network instrumentation, user identity, custom events, global span attributes, caught/uncaught error capture, session ID, and flush.

## Prerequisites

- **Android Studio** (latest stable) or the Android command-line SDK tools.
- **JDK 17–21** to run Gradle/AGP. Android Studio bundles a compatible JBR (JDK 21). The Android Gradle Plugin does **not** support JDK 25 — use 17–21.
- Android SDK with **API 36** platform and build-tools installed.
- **Gradle** (any recent version, e.g. via `brew install gradle`) — used once to generate the Gradle wrapper jar, which is not committed (repo policy: no binaries). Android Studio users can skip this; the IDE handles it.
- A **Last9 account** with a RUM client token. See the [Last9 docs](https://last9.io/docs/).
- SDK version: **`io.last9:rum-android:0.7.1`** (resolved from the Last9 CDN Maven repo configured in `settings.gradle.kts`).

## Quick Start

1. Copy the config template and fill it in:

   ```bash
   cp local.properties.example local.properties
   ```

   Edit `local.properties` and set:
   - `last9.baseUrl`, `last9.clientToken`, `last9.origin` — your Last9 RUM credentials
   - `sdk.dir` — *optional*; only needed if neither `ANDROID_HOME` nor `ANDROID_SDK_ROOT` is set (Android Studio sets it automatically)

   `local.properties` is git-ignored and must never be committed.

2. Generate the Gradle wrapper jar (first time only — `gradle-wrapper.jar` is a binary and is not committed):

   ```bash
   gradle wrapper
   ```

3. Build and install on a connected device/emulator:

   ```bash
   ./gradlew installDebug
   ```

   Or open the project in Android Studio and click **Run**.

## Configuration

Secret values live in `local.properties` and are surfaced into `BuildConfig` by `app/build.gradle.kts`. Non-secret values (`serviceName`, `serviceVersion`, `deploymentEnvironment`) are hardcoded in `RumExampleApplication.kt`.

| `local.properties` key | BuildConfig field | Description |
|------------------------|-------------------|-------------|
| `sdk.dir` | — | *Optional* local Android SDK path (build only); skip if `ANDROID_HOME`/`ANDROID_SDK_ROOT` is set |
| `last9.baseUrl` | `LAST9_BASE_URL` | OTLP endpoint, e.g. `https://otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>` |
| `last9.clientToken` | `LAST9_CLIENT_TOKEN` | Client token from the Last9 dashboard |
| `last9.origin` | `LAST9_ORIGIN` | Sent as the `X-LAST9-ORIGIN` header, e.g. `https://app.last9.io` |
| `last9.rumSdkVersion` | — | Last9 RUM Android SDK version to resolve from the [CDN Maven repo](https://cdn.last9.io/rum-sdk/android/maven/) (`io.last9:rum-android`). Optional; defaults to `0.7.1` |

## What the app demonstrates

- **Home** — `identify()` / `clearUser()`, `addEvent()` custom event, `spanAttributes()` global attributes, navigation to the other screens.
- **Network** — GET and POST to `jsonplaceholder.typicode.com` via an OkHttp client instrumented with `L9Rum.instrumentOkHttp(builder, context)`, emitting parent HTTP spans plus DNS/TCP/TLS/TTFB phase child spans. Requests run off the main thread.
- **Errors** — `captureError()` for a caught exception, a button that throws an uncaught exception (exercising automatic error instrumentation), plus `getSessionId()` and `flush()`.

Each screen is a real Navigation Compose route, so the SDK's automatic view tracking fires one view per screen.

## Verification

After running with a real token, exercise each screen, then open the Last9 dashboard. You should see:

- A **session** for the app run.
- A **view per screen** (Home, Network, Errors) as you navigate.
- **HTTP spans** for the GET and POST, each with **DNS / TCP / TLS / TTFB phase child spans**.
- A **captured error** from the Errors screen (both the caught `captureError` and the uncaught crash).
