# iOS OpenTelemetry - Last9 Integration

Send distributed traces from an iOS app to Last9 using OpenTelemetry Swift SDK. Auto-instruments URLSession network calls, tracks sessions and screen views, and injects W3C `traceparent` for backend correlation.

Uses **client monitoring tokens** (write-only, safe for mobile apps) with synthetic origins (`ios://com.yourcompany.yourapp`).

## Prerequisites

- Xcode 15+ / Swift 5.9+
- iOS 13+ deployment target
- A Last9 client monitoring token from [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens)

## Quick Start

### 1. Add SPM Dependencies

In Xcode: **File → Add Package Dependencies**, add these two packages:

```
https://github.com/open-telemetry/opentelemetry-swift-core.git  (from: 2.3.0)
https://github.com/open-telemetry/opentelemetry-swift.git       (from: 2.3.0)
```

Select these products for your target:

| Package | Product |
|---------|---------|
| opentelemetry-swift-core | `OpenTelemetryApi`, `OpenTelemetrySdk` |
| opentelemetry-swift | `OpenTelemetryProtocolExporterHTTP`, `URLSessionInstrumentation`, `ResourceExtension`, `NetworkStatus` |

### 2. Create a Client Monitoring Token

1. Go to [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens)
2. Click **Create New Token** → select **Client**
3. Set allowed origin to `ios://com.yourcompany.yourapp` (your app's bundle ID)
4. Copy the token and the endpoint URL

### 3. Copy source files into your project

Copy all files from `Sources/` into your Xcode project:
- `Last9OTel.swift` — core setup and public API
- `SessionManager.swift` — session lifecycle (15m inactivity / 4h max)
- `SessionStore.swift` — thread-safe state and file persistence
- `SessionSpanProcessor.swift` — injects session/view/user attributes into all spans
- `ViewManager.swift` — automatic UIKit view tracking + SwiftUI modifier
- `UserInfo.swift` — user identity model

### 4. Initialize in AppDelegate

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    Last9OTel.initialize(
        endpoint: "<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring",
        clientToken: "<your-client-token>",
        serviceName: "my-ios-app"
    )

    return true
}
```

Or for SwiftUI:

```swift
@main
struct YourApp: App {
    init() {
        Last9OTel.initialize(
            endpoint: "<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring",
            clientToken: "<your-client-token>",
            serviceName: "my-ios-app"
        )
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 5. That's it — network calls are auto-traced

Every `URLSession` request is now automatically traced with:
- HTTP method, URL, status code, latency
- W3C `traceparent` header injected (links to backend traces)
- Device model, OS version, app version attached

## Configuration

| Environment Variable | Description |
|---------------------|-------------|
| `LAST9_OTLP_ENDPOINT` | Last9 client monitoring endpoint |
| `LAST9_CLIENT_TOKEN` | Client token from [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens) |

## What's Auto-Instrumented

| Signal | Details |
|--------|---------|
| URLSession requests | Every `dataTask`, `data(from:)`, `download` call — latency, status, URL |
| W3C trace propagation | `traceparent` + `tracestate` headers injected into outgoing requests |
| Sessions | Auto-managed with 15m inactivity / 4h max duration, persisted to disk |
| Screen views (UIKit) | UIViewController swizzle — `view.id`, `view.name`, `view.time_spent` |
| Resource attributes | `device.model.identifier`, `os.name`, `os.version`, `service.version` |
| Network type | WiFi vs Cellular (iOS only) |

Every span automatically includes `session.id`, `view.id`, `view.name`, and `user.*` attributes (if set).

## User Identification

After login, identify the user so all subsequent spans carry user context:

```swift
Last9OTel.identify(id: "u_123", name: "Alice", email: "alice@example.com")
```

On logout:

```swift
Last9OTel.clearUser()
```

## SwiftUI View Tracking

UIKit views are tracked automatically. For SwiftUI, use the `.trackView(name:)` modifier:

```swift
ContentView()
    .trackView(name: "Home")
```

Or use the manual API for custom navigation flows:

```swift
Last9OTel.startView(name: "Onboarding Step 1")
// ... later ...
Last9OTel.endView()
```

## Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `sessionInactivityTimeout` | `900` (15 min) | Seconds of inactivity before session expires |
| `enableAutoViewTracking` | `true` | Swizzle UIViewController for auto view tracking |

```swift
Last9OTel.initialize(
    endpoint: "...",
    clientToken: "...",
    serviceName: "my-ios-app",
    sessionInactivityTimeout: 10 * 60,  // 10 minutes
    enableAutoViewTracking: false        // manual only
)
```

## Custom Spans

Track business-specific events:

```swift
let tracer = Last9OTel.tracer("auth")
let span = tracer.spanBuilder(spanName: "user.login")
    .setAttribute(key: "auth.method", value: "otp")
    .startSpan()

// ... your logic ...

span.setAttribute(key: "auth.success", value: true)
span.end()
```

See `Sources/ExampleUsage.swift` for more patterns (screen tracking, video playback, error handling).

## Verification

1. Run the app and trigger a network request
2. Open [Last9 Traces](https://app.last9.io) and search for your service name
3. You should see HTTP spans with `url.full`, `http.response.status_code`, `http.request.method`

## Security

This integration uses **client monitoring tokens** which are:
- **Write-only** — can send telemetry, cannot read or query data
- **Origin-scoped** — tied to your app's bundle ID (`ios://com.yourcompany.yourapp`)
- **Rate-limited** — server-side rate limiting prevents abuse

The token is safe to ship in your app binary.

## Project Structure

```
ios/
├── Package.swift                  # SPM dependencies
├── Sources/
│   ├── Last9OTel.swift            # Core setup + public API (identify, startView, endView)
│   ├── SessionManager.swift       # Session lifecycle, rollover, persistence restore
│   ├── SessionStore.swift         # Thread-safe state store + file persistence
│   ├── SessionSpanProcessor.swift # Injects session/view/user attrs into every span
│   ├── ViewManager.swift          # UIKit auto-tracking + SwiftUI modifier
│   ├── UserInfo.swift             # User identity model
│   ├── AppDelegate.swift          # Example initialization
│   └── ExampleUsage.swift         # Usage patterns (network, auth, views, identify)
├── .env.example                   # Credential template
└── README.md
```
