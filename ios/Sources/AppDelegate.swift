import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Initialize Last9 OpenTelemetry.
        //
        // After this call:
        //   - Every URLSession request is auto-traced (latency, status, URL)
        //   - W3C traceparent is auto-injected (links to backend traces)
        //   - Device, OS, app version are auto-attached to every span
        //
        // Uses a client monitoring token (write-only, safe for mobile apps).
        // Create the token at https://app.last9.io/control-plane/ingestion-tokens
        // with allowed origin: ios://com.yourcompany.yourapp
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

    func applicationDidEnterBackground(_ application: UIApplication) {
        Last9OTel.shared?.flush()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Last9OTel.shared?.shutdown()
    }
}
