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

## Verification

`gradle resolveLast9Rum` should print `rum-android-0.9.0.aar`.
