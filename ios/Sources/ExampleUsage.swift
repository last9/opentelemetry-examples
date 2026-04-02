import Foundation
import OpenTelemetryApi

// MARK: - Example 1: Network calls are automatic

/// Every URLSession call is auto-traced. No code changes needed.
/// The span captures: HTTP method, URL, status code, latency.
/// W3C traceparent is injected so backend traces link to this request.
func fetchContent(id: String) async throws -> Data {
    let url = URL(string: "https://api.example.com/v1/content/\(id)")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
    // That's it — this request is already traced in Last9.
}

// MARK: - Example 2: Custom span for business logic

/// Track a login flow as a single span with attributes.
func handleLogin(phone: String, otp: String) async throws {
    let tracer = Last9OTel.tracer("auth")
    let span = tracer.spanBuilder(spanName: "user.login")
        .setAttribute(key: "auth.method", value: "otp")
        .startSpan()

    defer { span.end() }

    do {
        let url = URL(string: "https://api.example.com/v1/auth/verify-otp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["phone": phone, "otp": otp])
        let (_, response) = try await URLSession.shared.data(for: request)

        let httpResponse = response as! HTTPURLResponse
        span.setAttribute(key: "auth.success", value: httpResponse.statusCode == 200)
        span.setAttribute(key: "http.status_code", value: httpResponse.statusCode)
    } catch {
        span.setAttribute(key: "auth.success", value: false)
        span.addEvent(name: "exception", attributes: [
            "exception.message": .string(error.localizedDescription)
        ])
        throw error
    }
}

// MARK: - Example 3: Screen views are automatic (UIKit)

import UIKit

/// UIKit views are auto-tracked — no code needed.
/// Every UIViewController's viewDidAppear/viewDidDisappear is swizzled.
/// The view name defaults to the class name (e.g., "HomeViewController").
/// Attributes added automatically: view.id, view.name, view.time_spent.
class HomeViewController: UIViewController {
    // Nothing needed! This screen is tracked automatically.
    // To customize the view name, set it in viewDidLoad:
    //   self.last9ViewName = "Home"
}

// MARK: - Example 4: Track video playback events

func trackPlaybackStart(contentId: String, contentTitle: String) {
    let tracer = Last9OTel.tracer("player")
    let span = tracer.spanBuilder(spanName: "playback.start")
        .setAttribute(key: "content.id", value: contentId)
        .setAttribute(key: "content.title", value: contentTitle)
        .setAttribute(key: "player.type", value: "avplayer")
        .startSpan()
    span.end()
}

func trackPlaybackError(contentId: String, error: Error, bufferDuration: Double) {
    let tracer = Last9OTel.tracer("player")
    let span = tracer.spanBuilder(spanName: "playback.error")
        .setAttribute(key: "content.id", value: contentId)
        .setAttribute(key: "error.message", value: error.localizedDescription)
        .setAttribute(key: "player.buffer_duration_ms", value: Int(bufferDuration * 1000))
        .startSpan()
    span.setStatus(.error(description: error.localizedDescription))
    span.end()
}

// MARK: - Example 5: User identification

/// After login, identify the user so all subsequent spans carry user context.
/// session.id, view.id, and user.* are injected into every span automatically.
func onLoginComplete(userId: String, userName: String, email: String) {
    Last9OTel.identify(
        id: userId,
        name: userName,
        email: email
    )
}

/// On logout, clear user identity.
func onLogout() {
    Last9OTel.clearUser()
}

// MARK: - Example 6: Custom view name (UIKit)

/// Override the auto-generated view name with a custom one.
/// By default, the class name ("SettingsViewController") is used.
class SettingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Override the auto-detected name for this screen
        self.last9ViewName = "Settings"
    }
}

// MARK: - Example 7: SwiftUI view tracking

import SwiftUI

/// For SwiftUI views, use the .trackView(name:) modifier.
/// UIKit views are tracked automatically via swizzling — no code needed.
@available(iOS 13.0, *)
struct CheckoutView: SwiftUI.View {
    var body: some SwiftUI.View {
        VStack {
            Text("Checkout")
        }
        .trackView(name: "Checkout")
    }
}

// MARK: - Example 8: Manual view tracking (custom navigation)

/// For custom navigation flows that don't use UIViewController,
/// call startView/endView directly.
func showOnboardingStep(step: Int) {
    Last9OTel.startView(name: "Onboarding Step \(step)")
}

func finishOnboarding() {
    Last9OTel.endView()
}
