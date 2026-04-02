# iOS OpenTelemetry - Last9 Integration

Send distributed traces from an iOS app to Last9 using the [Last9 RUM SDK](https://github.com/last9/last9-ios-swift-sdk). Auto-instruments URLSession network calls, tracks sessions and screen views, and injects W3C `traceparent` for backend correlation.

Uses **client monitoring tokens** (write-only, safe for mobile apps) with synthetic origins (`ios://com.yourcompany.yourapp`).

## Prerequisites

- Xcode 15+ / Swift 5.9+
- iOS 13+ deployment target
- A Last9 client monitoring token from [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens)

## Quick Start

### 1. Add the Last9 RUM SDK via SPM

In Xcode: **File → Add Package Dependencies**, enter:

```
https://github.com/last9/last9-ios-swift-sdk
```

Select **Last9RUM** as the product to add to your target.

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/last9/last9-ios-swift-sdk", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Last9RUM", package: "last9-ios-swift-sdk"),
    ]),
]
```

### 2. Create a Client Monitoring Token

1. Go to [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens)
2. Click **Create New Token** → select **Client**
3. Set allowed origin to `ios://com.yourcompany.yourapp` (your app's bundle ID)
4. Copy the token and the endpoint URL

### 3. Initialize in AppDelegate

```swift
import Last9RUM

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    Last9RUM.initialize(
        endpoint: "<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring",
        clientToken: "<your-client-token>",
        serviceName: "my-ios-app"
    )

    return true
}
```

Or for SwiftUI:

```swift
import Last9RUM

@main
struct YourApp: App {
    init() {
        Last9RUM.initialize(
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

### 4. That's it — network calls are auto-traced

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
| App launch time | Cold and warm start duration (process start → first viewDidAppear) |
| Frame rate | Slow frames (>25ms) and frozen frames (>700ms) per view via CADisplayLink |
| CPU / Memory | Per-view CPU usage and resident memory sampling via mach_task_basic_info |
| User interactions | Tap tracking via UIApplication.sendEvent swizzle with target info |
| Network timing | DNS, TLS, TTFB, transfer breakdown from URLSessionTaskMetrics |
| Hangs (ANR) | Background thread detects main thread blocks > 2s, captures stack trace |
| Watchdog terminations | Detects abnormal previous termination (0x8badf00d) on next launch |
| Signal crashes | SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGTRAP with crash markers |
| Resource attributes | `device.model.identifier`, `os.name`, `os.version`, `service.version` |
| Network type | WiFi vs Cellular (iOS only) |

Every span automatically includes `session.id`, `view.id`, `view.name`, and `user.*` attributes (if set).

## User Identification

After login, identify the user so all subsequent spans carry user context:

```swift
Last9RUM.identify(id: "u_123", name: "Alice", email: "alice@example.com")
```

On logout:

```swift
Last9RUM.clearUser()
```

## SwiftUI View Tracking

UIKit views are tracked automatically. For SwiftUI, use the `.trackView(name:)` modifier:

```swift
ContentView()
    .trackView(name: "Home")
```

Or use the manual API for custom navigation flows:

```swift
Last9RUM.startView(name: "Onboarding Step 1")
// ... later ...
Last9RUM.endView()
```

## Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `sessionInactivityTimeout` | `900` (15 min) | Seconds of inactivity before session expires |
| `enableAutoViewTracking` | `true` | Swizzle UIViewController for auto view tracking |
| `hangThreshold` | `2.0` (2 sec) | Main thread block time to report as a hang. `0` to disable |

```swift
Last9RUM.initialize(
    endpoint: "...",
    clientToken: "...",
    serviceName: "my-ios-app",
    sessionInactivityTimeout: 10 * 60,  // 10 minutes
    enableAutoViewTracking: false,       // manual only
    hangThreshold: 3.0                   // 3-second hang threshold
)
```

## Custom Spans

Track business-specific events:

```swift
let tracer = Last9RUM.tracer("auth")
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
├── Package.swift              # SPM: imports last9/last9-ios-swift-sdk
├── Sources/
│   ├── AppDelegate.swift      # Example initialization
│   └── ExampleUsage.swift     # Usage patterns
├── .env.example               # Credential template
└── README.md
```

The SDK source lives in [last9/last9-ios-swift-sdk](https://github.com/last9/last9-ios-swift-sdk).
