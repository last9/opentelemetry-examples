# Android RUM Activity Init

A minimal Android app showing Last9 RUM initialization from an `Activity` without a custom `Application` subclass. It initializes with `activity.application`, instruments OkHttp, and makes external API calls that should show as spans in Last9.

## Prerequisites

- Android Studio or Android SDK command-line tools
- JDK 17-21
- Android SDK API 36
- Gradle installed locally to generate the wrapper jar, or Android Studio
- A Last9 RUM client token

## Quick Start

1. Create local config:

   ```bash
   cp local.properties.example local.properties
   ```

2. Edit `local.properties` with your Last9 values.

3. Generate a Gradle wrapper jar if needed:

   ```bash
   gradle wrapper
   ```

4. Build or run:

   ```bash
   ./gradlew installDebug
   ```

## Configuration

| Key | Description |
|-----|-------------|
| `last9.baseUrl` | Last9 OTLP endpoint, for example `https://otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>` |
| `last9.clientToken` | Last9 RUM client token |
| `last9.origin` | Origin sent as `X-LAST9-ORIGIN` |
| `last9.rumSdkVersion` | SDK version. Defaults to `0.9.0` |

The SDK resolves from the Last9 CDN Maven repository:

```kotlin
maven { url = uri("https://cdn.last9.io/rum-sdk/android/maven/") }
implementation("io.last9:rum-android:0.9.0")
```

## Verification

Tap the GET/POST buttons. In Last9 you should see a session for `android-rum-activity-init` and HTTP spans for `jsonplaceholder.typicode.com` and `httpbin.org`.
