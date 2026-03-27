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

// MARK: - Example 3: Track screen views (UIKit)

import UIKit

class HomeViewController: UIViewController {
    private var screenSpan: Span?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let tracer = Last9OTel.tracer("navigation")
        screenSpan = tracer.spanBuilder(spanName: "screen.view")
            .setAttribute(key: "screen.name", value: "HomeScreen")
            .setAttribute(key: "screen.class", value: String(describing: type(of: self)))
            .startSpan()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        screenSpan?.end()
        screenSpan = nil
    }
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
