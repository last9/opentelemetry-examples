# iOS RUM SPM Demo

A minimal iOS SwiftUI demo for the Last9 RUM iOS SDK via Swift Package Manager. The package resolves the SDK XCFramework from the Last9 CDN and demonstrates `L9Rum.shared.initialize(config:)`, `URLSession` spans, error capture, and `shutdown()`.

## Prerequisites

- Xcode 15+
- iOS 16+ simulator or device
- XcodeGen if you want to generate the included fresh Xcode project: `brew install xcodegen`
- A Last9 RUM client token

## Quick Start

1. Copy secrets:

   ```bash
   cp Secrets.example.xcconfig Secrets.xcconfig
   ```

2. Edit `Secrets.xcconfig` with your Last9 values.

3. Resolve the Swift package:

   ```bash
   swift package resolve
   ```

4. Generate and open the Xcode project:

   ```bash
   xcodegen generate
   open Last9RUMSPMDemo.xcodeproj
   ```

5. Run the app and tap **Initialize SDK**, then the API buttons.

## Configuration

| Key | Description |
|-----|-------------|
| `LAST9_BASE_URL` | Last9 OTLP endpoint without `https://` in `Secrets.xcconfig` |
| `LAST9_CLIENT_TOKEN` | Last9 RUM client token |
| `LAST9_ORIGIN` | Origin without `https://` in `Secrets.xcconfig` |

The SDK is resolved through this SwiftPM binary target:

```swift
.binaryTarget(
    name: "Last9RUM",
    url: "https://cdn.last9.io/rum-sdk/ios/builds/0.9.0/Last9RUM.xcframework.zip",
    checksum: "a340f15d22d1d594731c3eff17bbc806f1c732962aa39daab072451ecde23ebf"
)
```

Checksum source:

```text
https://cdn.last9.io/rum-sdk/ios/builds/0.9.0/Last9RUM.xcframework.zip.sha256
```

## Verification

After tapping through the app, Last9 should show a session for `ios-rum-spm-demo` and API spans for `jsonplaceholder.typicode.com` and `httpbin.org`. Tapping **Shutdown SDK** flushes and tears down the SDK for a clean flow boundary.
