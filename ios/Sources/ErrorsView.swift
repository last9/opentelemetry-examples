import SwiftUI
import Last9RUM

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Errors Tab — manual + automatic error capture.
//  Note: the React Native reference has an ANR simulation button; iOS has no
//  ANR detection (anrDetectionEnabled is Android-only and absent from
//  L9RumConfig on iOS), so that button is omitted here.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Generic demo error carrying a message so captureError reports it verbatim.
struct DemoError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ErrorsView: View {
    var body: some View {
        NavigationStack {
            ScreenScroll {
                FeatureBadge(features: [
                    "Manual Error Capture (captureError)",
                    "Caught TypeError / cast failure",
                    "Caught Network Error",
                    "Promise / async rejection path",
                    "Stack Traces with Context",
                    "Uncaught crash (errorInstrumentation)",
                ])
                Hint("errorInstrumentation: true auto-captures unhandled errors. iOS has no ANR detection (Android-only), so that reference button is omitted.")

                ErrorButton(title: "Capture Error (with context)",
                            subtitle: "captureError(err, context: [screen, severity, user_action])",
                            color: Theme.error) {
                    let err = DemoError(message: "Checkout failed: payment gateway timeout")
                    L9Rum.shared.captureError(err, context: [
                        "screen": "Checkout",
                        "severity": "high",
                        "user_action": "submit_payment",
                        "cart_total": 149.99,
                    ])
                    EventLog.shared.add("captureError: payment gateway timeout")
                }

                ErrorButton(title: "Capture TypeError",
                            subtitle: "Simulates a failed cast (accessing wrong type)",
                            color: Theme.warning) {
                    let value: Any = "not-a-number"
                    if (value as? Int) == nil {
                        let err = NSError(domain: "TypeError", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Cannot read property of undefined (expected Int, got String)",
                        ])
                        L9Rum.shared.captureError(err, context: [
                            "screen": "ErrorsDemo",
                            "type": "TypeError",
                        ])
                        EventLog.shared.add("captureError: TypeError")
                    }
                }

                ErrorButton(title: "Capture Network Error",
                            subtitle: "Simulates a failed API call error",
                            color: Color(red: 0.933, green: 0.353, blue: 0.141)) {
                    let err = DemoError(message: "NetworkError: Failed to fetch /todos")
                    L9Rum.shared.captureError(err, context: [
                        "screen": "Todos",
                        "endpoint": "/todos",
                        "http_method": "GET",
                        "retry_count": 3,
                    ])
                    EventLog.shared.add("captureError: NetworkError")
                }

                ErrorButton(title: "Async Rejection",
                            subtitle: "Throws inside an async Task and captures it",
                            color: Theme.violet) {
                    Task {
                        do {
                            try await failingAsyncWork()
                        } catch {
                            L9Rum.shared.captureError(error, context: ["source": "promise_rejection"])
                            EventLog.shared.add("captureError: async rejection")
                        }
                    }
                }

                ErrorButton(title: "Capture Error with Stack Trace",
                            subtitle: "Deep call stack to demonstrate trace capture",
                            color: Theme.lilac) {
                    func level3() throws {
                        throw DemoError(message: "Deep stack: database connection pool exhausted")
                    }
                    func level2() throws { try level3() }
                    func level1() throws { try level2() }
                    do {
                        try level1()
                    } catch {
                        L9Rum.shared.captureError(error, context: [
                            "screen": "ErrorsDemo",
                            "stack_depth": 3,
                        ])
                        EventLog.shared.add("captureError: deep stack trace")
                    }
                }

                ErrorButton(title: "Fire Multiple Errors (Burst)",
                            subtitle: "5 rapid errors to test batching & export",
                            color: Theme.ok) {
                    for i in 1...5 {
                        L9Rum.shared.captureError(DemoError(message: "Burst error #\(i)"), context: [
                            "index": i,
                            "screen": "ErrorsDemo",
                        ])
                    }
                    EventLog.shared.add("captureError: 5 burst errors")
                }

                ErrorButton(title: "Raise UNCAUGHT error (crash)",
                            subtitle: "Force-unwrap nil in a Task — auto-captured, crashes",
                            color: Color(red: 0.992, green: 0.475, blue: 0.659)) {
                    EventLog.shared.add("raising uncaught error (force-unwrap nil)…")
                    Task {
                        let value: Int? = nil
                        _ = value!  // intentional crash
                    }
                }
            }
            .navigationTitle("Errors")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func failingAsyncWork() async throws {
        try await Task.sleep(nanoseconds: 10_000_000)
        throw DemoError(message: "Unhandled: session token expired")
    }
}
