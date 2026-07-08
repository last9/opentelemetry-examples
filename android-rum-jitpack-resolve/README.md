# Android RUM Gradle Resolve

A clean Gradle resolver example for `io.last9:rum-android:0.9.0`. Use this when validating that a library or JitPack build can resolve the Last9 Android RUM SDK from the CDN Maven repository.

## Prerequisites

- JDK 17+
- Gradle

## Quick Start

```bash
gradle resolveLast9Rum
```

Override the version if needed:

```bash
LAST9_RUM_ANDROID_VERSION=0.9.0 gradle resolveLast9Rum
```

## Configuration

No secrets are required.

| Variable | Description |
|----------|-------------|
| `LAST9_RUM_ANDROID_VERSION` | Android SDK version to resolve. Defaults to `0.9.0` |

## Library/JitPack Snippet

Add the Last9 CDN Maven repository in `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://cdn.last9.io/rum-sdk/android/maven/") }
    }
}
```

Add the SDK in a module `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.last9:rum-android:0.9.0")
}
```

## v0.9.0 Lifecycle APIs

Version `0.9.0` adds embedded/per-flow lifecycle support. After resolving the CDN artifact, an app or library can initialize RUM for a flow, attach flow attributes, shut it down, and later re-initialize cleanly:

```kotlin
L9Rum.initialize(application, config)
L9Rum.spanAttributes(mapOf("example.flow" to "checkout"))

if (L9Rum.isActive()) {
    L9Rum.shutdown()
}

L9Rum.initialize(application, config)
```

Do not run two integrations at the same time. A second `initialize()` while RUM is active is ignored until `shutdown()` tears down the active integration.

## Verification

`gradle resolveLast9Rum` should print `rum-android-0.9.0.aar`.
