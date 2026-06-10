import SwiftUI
import Last9RUM

@main
struct RUMExampleApp: App {

    init() {
        // Initialize the Last9 RUM SDK exactly once, at app entry point —
        // before any view's `.task`/`.onAppear` fires, so early network calls
        // and view starts are captured.
        //
        // This mirrors the React Native reference app's rich RUM_CONFIG. In
        // SDK 0.7.1 every L9RumConfig field is a `let`, so ALL options are
        // passed through the initializer (the README's `config.x = ...`
        // mutation pattern does not compile).
        //
        // Secrets (baseUrl, clientToken, origin) come from Secrets.xcconfig via
        // Info.plist; non-secret values are inlined and exposed via RUMConfig
        // so the Profile tab can render the active config.
        L9Rum.shared.initialize(config: RUMConfig.makeConfig())

        EventLog.shared.add("L9Rum.initialize() (called at app launch)")
        if let id = L9Rum.shared.getSessionId() {
            EventLog.shared.add("sessionId: \(String(id.prefix(12)))…")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
