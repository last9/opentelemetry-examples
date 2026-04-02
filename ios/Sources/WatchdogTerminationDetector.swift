import Foundation
import OpenTelemetryApi

/// Detects watchdog terminations (0x8badf00d) from the previous app session.
///
/// iOS kills apps that block the main thread too long during lifecycle transitions
/// (launch, backgrounding, foregrounding). The watchdog timeout is ~20 seconds.
/// These appear as `0x8badf00d` ("ate bad food") in crash logs.
///
/// Detection is heuristic: on launch, if the previous session was active (no clean
/// shutdown recorded) and no crash handler fired, the previous termination was likely
/// a watchdog kill or OOM.
///
/// The detector persists two flags in the caches directory:
/// - `last9_app_state.json`: `isRunning` + `crashHandlerFired` + previous session ID
///
/// On each launch: read previous state → if abnormal → emit FATAL log → reset state.
final class WatchdogTerminationDetector {

    private let logger: Logger
    private let stateURL: URL

    init() {
        self.logger = OpenTelemetry.instance.loggerProvider
            .loggerBuilder(instrumentationScopeName: "watchdog")
            .build()
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.stateURL = cacheDir.appendingPathComponent("last9_app_state.json")
    }

    // MARK: - Public

    /// Call once at startup, after SessionManager has started.
    /// Checks the previous session's shutdown state and emits a log if abnormal.
    func checkPreviousSession() {
        guard let previous = loadState() else {
            // First launch or state file missing — nothing to check
            markRunning()
            return
        }

        if previous.isRunning && !previous.crashHandlerFired {
            // Previous session was active, no crash handler fired →
            // likely a watchdog kill, OOM, or force-quit
            emitWatchdogTermination(
                previousSessionId: previous.sessionId,
                appState: previous.appState
            )
        }

        // Reset for this session
        markRunning()
    }

    /// Mark the app as cleanly shutting down. Call from `appWillTerminate`.
    func markCleanShutdown() {
        updateState { state in
            state.isRunning = false
        }
    }

    /// Mark that the crash handler fired (so we don't double-report as watchdog).
    func markCrashHandlerFired() {
        updateState { state in
            state.crashHandlerFired = true
        }
    }

    /// Update the persisted app state (foreground/background).
    func updateAppState(_ appState: String) {
        updateState { state in
            state.appState = appState
        }
    }

    /// Update the persisted session ID (so watchdog logs link to the right session).
    func updateSessionId(_ sessionId: String) {
        updateState { state in
            state.sessionId = sessionId
        }
    }

    // MARK: - Persistence

    private struct AppState: Codable {
        var isRunning: Bool
        var crashHandlerFired: Bool
        var sessionId: String?
        var appState: String?  // "foreground" or "background"
    }

    private func markRunning() {
        let sessionId = SessionStore.shared.currentSessionId
        let state = AppState(
            isRunning: true,
            crashHandlerFired: false,
            sessionId: sessionId,
            appState: "foreground"
        )
        saveState(state)
    }

    private func loadState() -> AppState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: stateURL)
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: stateURL)
            return nil
        }
    }

    private func saveState(_ state: AppState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // Non-fatal — we'll miss detection on next launch
        }
    }

    private func updateState(_ mutate: (inout AppState) -> Void) {
        var state = loadState() ?? AppState(
            isRunning: true,
            crashHandlerFired: false,
            sessionId: nil,
            appState: nil
        )
        mutate(&state)
        saveState(state)
    }

    // MARK: - Log Emission

    private func emitWatchdogTermination(previousSessionId: String?, appState: String?) {
        var attrs: [String: AttributeValue] = [
            "event.name": .string("watchdog_termination"),
            "watchdog.type": .string("abnormal_termination"),
        ]

        if let sessionId = previousSessionId {
            attrs["watchdog.previous_session.id"] = .string(sessionId)
        }

        if let appState = appState {
            attrs["watchdog.previous_app_state"] = .string(appState)
        }

        logger.logRecordBuilder()
            .setBody(.string("watchdog_termination"))
            .setSeverity(.fatal)
            .setAttributes(attrs)
            .emit()
    }
}
