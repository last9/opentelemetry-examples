import Foundation

// MARK: - Persisted Session (Codable for file storage)

struct PersistedSession: Codable {
    var id: String
    var previousId: String?
    var startedAt: TimeInterval    // Date.timeIntervalSince1970
    var lastActivityAt: TimeInterval
}

// MARK: - SessionStore

/// Thread-safe, single source of truth for session, view, and user state.
///
/// `SessionSpanProcessor` reads from here on every span start (hot path).
/// Uses `os_unfair_lock` for zero-overhead synchronization — no dispatch queues,
/// no priority inversion risk on URLSession delegate threads.
///
/// File persistence uses the app's caches directory (survives app kills, not reinstalls,
/// OS can evict under storage pressure — acceptable for session state).
final class SessionStore {
    static let shared = SessionStore()

    /// Heap-allocated lock — `os_unfair_lock` requires a stable memory address.
    private let lock: UnsafeMutablePointer<os_unfair_lock_s> = {
        let ptr = UnsafeMutablePointer<os_unfair_lock_s>.allocate(capacity: 1)
        ptr.initialize(to: os_unfair_lock())
        return ptr
    }()

    // Session state
    private var _currentSessionId: String?
    private var _previousSessionId: String?
    private var _sessionStartedAt: Date?
    private var _sessionLastActivityAt: Date?

    // View state
    private var _currentViewId: String?
    private var _currentViewName: String?
    private var _viewStartedAt: Date?

    // User state
    private var _currentUser: UserInfo?

    // File persistence
    private let persistenceURL: URL

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.persistenceURL = cacheDir.appendingPathComponent("last9_session.json")
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    // MARK: - Session Accessors

    var currentSessionId: String? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _currentSessionId
    }

    var previousSessionId: String? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _previousSessionId
    }

    var sessionStartedAt: Date? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _sessionStartedAt
    }

    var sessionLastActivityAt: Date? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _sessionLastActivityAt
    }

    // MARK: - View Accessors

    var currentViewId: String? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _currentViewId
    }

    var currentViewName: String? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _currentViewName
    }

    // MARK: - User Accessors

    var currentUser: UserInfo? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _currentUser
    }

    // MARK: - Session Mutations

    func setCurrentSession(id: String, previousId: String?, startedAt: Date) {
        os_unfair_lock_lock(lock)
        _currentSessionId = id
        _previousSessionId = previousId
        _sessionStartedAt = startedAt
        _sessionLastActivityAt = startedAt
        os_unfair_lock_unlock(lock)
        persistToDisk()
    }

    func updateLastActivity() {
        os_unfair_lock_lock(lock)
        _sessionLastActivityAt = Date()
        os_unfair_lock_unlock(lock)
        persistToDisk()
    }

    func clearSession() {
        os_unfair_lock_lock(lock)
        _previousSessionId = _currentSessionId
        _currentSessionId = nil
        _sessionStartedAt = nil
        _sessionLastActivityAt = nil
        os_unfair_lock_unlock(lock)
    }

    // MARK: - View Mutations

    func beginView(id: String, name: String) {
        os_unfair_lock_lock(lock)
        _currentViewId = id
        _currentViewName = name
        _viewStartedAt = Date()
        os_unfair_lock_unlock(lock)
    }

    /// Ends the current view and returns `time_spent` in milliseconds.
    func endView() -> Int? {
        os_unfair_lock_lock(lock)
        let startedAt = _viewStartedAt
        _currentViewId = nil
        _currentViewName = nil
        _viewStartedAt = nil
        os_unfair_lock_unlock(lock)

        guard let startedAt = startedAt else { return nil }
        return Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    // MARK: - User Mutations

    func setUser(_ user: UserInfo?) {
        os_unfair_lock_lock(lock)
        _currentUser = user
        os_unfair_lock_unlock(lock)
    }

    // MARK: - File Persistence

    func loadPersistedSession() -> PersistedSession? {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let session = try JSONDecoder().decode(PersistedSession.self, from: data)
            return session
        } catch {
            // Corrupted file — remove it
            try? FileManager.default.removeItem(at: persistenceURL)
            return nil
        }
    }

    private func persistToDisk() {
        os_unfair_lock_lock(lock)
        guard let id = _currentSessionId, let startedAt = _sessionStartedAt else {
            os_unfair_lock_unlock(lock)
            return
        }
        let session = PersistedSession(
            id: id,
            previousId: _previousSessionId,
            startedAt: startedAt.timeIntervalSince1970,
            lastActivityAt: (_sessionLastActivityAt ?? startedAt).timeIntervalSince1970
        )
        os_unfair_lock_unlock(lock)

        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // File write failure is non-fatal — session will be recreated on next launch
        }
    }

    func clearPersistedSession() {
        try? FileManager.default.removeItem(at: persistenceURL)
    }
}
