import Foundation
import SwiftUI

/// A single timestamped entry in the global event log.
struct LogEntry: Identifiable {
    let id: Int
    let ts: String
    let msg: String
}

/// Global event log shared across every tab — mirrors the React Native
/// reference app's `addLog` / `useLogs`. SDK calls and route changes append
/// here; the Profile tab's debug sheet renders the full list.
@MainActor
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var entries: [LogEntry] = []
    private var nextId = 0

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {}

    /// Append a message. Safe to call from any thread/context.
    nonisolated func add(_ msg: String) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self._add(msg) }
        } else {
            Task { @MainActor in self._add(msg) }
        }
    }

    private func _add(_ msg: String) {
        nextId += 1
        let entry = LogEntry(id: nextId, ts: Self.formatter.string(from: Date()), msg: msg)
        entries.insert(entry, at: 0)
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }
    }
}
