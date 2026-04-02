import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

#if canImport(UIKit)
import UIKit
#endif

/// Measures cold and warm app launch time.
///
/// Cold start: process creation → first `viewDidAppear` (full initialization).
/// Warm start: `willEnterForeground` → first `viewDidAppear` (app resumed from background).
///
/// Uses `ProcessInfo.processInfo.systemUptime` for process start time (monotonic clock,
/// not affected by wall clock changes).
///
/// Datadog and Sentry both auto-track this metric. We emit a span with `app.launch.duration_ms`
/// and `app.launch.type` (cold/warm).
final class AppLaunchTracker {
    /// Process start time (monotonic). Captured as early as possible via static initializer.
    private static let processStartTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private let tracer: Tracer
    private var coldLaunchRecorded = false
    private var warmLaunchStartTime: TimeInterval?

    #if canImport(UIKit)
    private var foregroundObserver: NSObjectProtocol?
    #endif

    init(tracerProvider: TracerProvider) {
        self.tracer = tracerProvider.get(
            instrumentationName: "app_launch",
            instrumentationVersion: nil
        )
    }

    // MARK: - Public

    func start() {
        #if canImport(UIKit)
        // Listen for foreground events to track warm launches
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.warmLaunchStartTime = ProcessInfo.processInfo.systemUptime
        }
        #endif
    }

    /// Call from the first `viewDidAppear` (or from ViewManager on first view start).
    func recordFirstViewAppeared() {
        let now = ProcessInfo.processInfo.systemUptime

        if !coldLaunchRecorded {
            // Cold launch: process start → now
            let durationMs = Int((now - Self.processStartTime) * 1000)
            emitLaunchSpan(type: "cold", durationMs: durationMs)
            coldLaunchRecorded = true
        } else if let warmStart = warmLaunchStartTime {
            // Warm launch: foreground → now
            let durationMs = Int((now - warmStart) * 1000)
            emitLaunchSpan(type: "warm", durationMs: durationMs)
            warmLaunchStartTime = nil
        }
    }

    func shutdown() {
        #if canImport(UIKit)
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        #endif
    }

    // MARK: - Span Emission

    private func emitLaunchSpan(type: String, durationMs: Int) {
        let span = tracer.spanBuilder(spanName: "app.launch")
            .setAttribute(key: "app.launch.type", value: type)
            .setAttribute(key: "app.launch.duration_ms", value: durationMs)
            .startSpan()
        span.end()
    }
}
