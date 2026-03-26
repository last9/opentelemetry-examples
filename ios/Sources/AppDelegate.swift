import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Initialize Last9 OpenTelemetry.
        //
        // After this call, automatically:
        //   - Every URLSession request is traced (latency, status, URL)
        //   - W3C traceparent is injected (links to backend traces)
        //   - Device, OS, app version attached per OTel semantic conventions
        //   - App lifecycle events emitted (active, inactive, background, foreground, terminate)
        //   - NSException crashes captured with stack traces
        //   - Flush on background + shutdown on terminate handled automatically
        Last9OTel.initialize(
            endpoint: ProcessInfo.processInfo.environment["LAST9_OTLP_ENDPOINT"]
                ?? "<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring",
            clientToken: ProcessInfo.processInfo.environment["LAST9_CLIENT_TOKEN"]
                ?? "<your-client-token>",
            serviceName: "my-ios-app",
            environment: "staging"
        )

        return true
    }

    // No need for applicationDidEnterBackground / applicationWillTerminate —
    // Last9OTel handles lifecycle automatically via NotificationCenter observers.
}
