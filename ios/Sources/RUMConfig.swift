import Foundation
import Last9RUM

/// Builds the Last9 RUM `L9RumConfig` (mirroring the React Native reference
/// app's `RUM_CONFIG`) and exposes the non-secret values so the Profile tab can
/// render an "Active SDK Config" card.
///
/// Secrets (`baseUrl`, `clientToken`, `origin`) are injected from
/// `Secrets.xcconfig` into the app's `Info.plist` at build time and read at
/// runtime; everything else is inlined here.
///
/// ## Why the URLs have no scheme
/// xcconfig treats `//` as the start of a comment, so a value such as
/// `https://otlp-ext-aps1.last9.io/...` is silently truncated to `https:`.
/// To work around this the secrets file stores URLs WITHOUT the `https://`
/// scheme (host + path only). This reader re-adds `https://`.
enum RUMConfig {

    // MARK: - Non-secret config values (also shown on the Profile tab)

    static let serviceName = "rum-ios-example"
    static let serviceVersion = "1.0.0"
    static let appBuildId = "1.0.0-dev"
    static let deploymentEnvironment = "development"
    static let sampleRate = 100
    static let propagationMode = "preserve"

    // MARK: - Browser RUM (WebView correlation)

    /// CDN build of the Last9 Browser RUM SDK that the WebView tab boots inside
    /// the page so its spans correlate with the native session/view. Matches the
    /// build the native SDK pins by default.
    static let browserRumCdnUrl = "https://cdn.last9.io/rum-sdk/builds/2.5.0-alpha/l9.umd.js"

    // MARK: - Config builder

    static func makeConfig() -> L9RumConfig {
        L9RumConfig(
            baseUrl: secret("LAST9_BASE_URL", url: true),
            clientToken: secret("LAST9_CLIENT_TOKEN"),
            serviceName: serviceName,
            serviceVersion: serviceVersion,
            deploymentEnvironment: deploymentEnvironment,
            appBuildId: appBuildId,
            sampleRate: sampleRate,
            debugLogs: true,
            resourceAttributes: [
                "app.platform": "ios",
                "device.type": "mobile",
            ],
            networkInstrumentation: true,
            errorInstrumentation: true,
            // Resource monitoring (CPU/memory) — 5s sampling interval.
            resourceMonitoringEnabled: true,
            resourceSamplingIntervalMs: 5000,
            // W3C Baggage propagation.
            baggage: L9BaggageConfig(
                enabled: true,
                allowedKeys: [
                    "session.id",
                    "user.id",
                    "deployment.environment",
                    "service.name",
                ]
            ),
            // Origin is required for client_monitoring tokens.
            origin: secret("LAST9_ORIGIN", url: true),
            // Keep network spans on the view's trace so they surface in the
            // Sessions → APIs tab (filtered by the view's traceId).
            isolateTracePerRequest: false,
            // Native URLSession interception is on (this is a native app, not a
            // JS/Dart bridge).
            nativeNetworkInterception: true,
            // Only suppress image/CDN resources; keep public API calls visible.
            ignorePatterns: L9NetworkIgnorePatterns(
                fullUrl: [
                    .regex("^https://images\\.pexels\\.com/photos/", options: [.caseInsensitive]),
                ],
                pathname: [
                    .regex("\\.(png|jpe?g|webp)$", options: [.caseInsensitive]),
                ],
                hostname: [
                    .regex("(^|\\.)loremflickr\\.com$", options: [.caseInsensitive]),
                ]
            ),
            propagationMode: .preserve,
            // Auto-load Browser RUM into instrumented WebViews so the page's
            // spans share this app's session.id / native.view.id.
            webViewAutoLoadBrowserRum: true,
            webViewBrowserRumCdnUrl: browserRumCdnUrl
        )
    }

    // MARK: - Secrets reader

    /// True when the developer has replaced the placeholder values.
    static var isConfigured: Bool {
        let token = secret("LAST9_CLIENT_TOKEN")
        return !token.isEmpty
            && token != "your-client-token"
            && !secret("LAST9_BASE_URL", url: true).contains("your-org")
    }

    private static func secret(_ key: String, url: Bool = false) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard url, !raw.isEmpty,
              !raw.hasPrefix("http://"), !raw.hasPrefix("https://") else {
            return raw
        }
        return "https://\(raw)"
    }
}
