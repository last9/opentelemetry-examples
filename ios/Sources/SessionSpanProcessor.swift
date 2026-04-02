import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Injects `session.id`, `session.previous_id`, `view.id`, `view.name`, and `user.*`
/// attributes into every span at start time.
///
/// Registered as the **first** processor in the `TracerProviderBuilder` chain so that
/// attributes are present before `BatchSpanProcessor` queues the span for export.
///
/// Reads from `SessionStore.shared` — no owned state, no async boundaries.
/// Attribute names match the browser SDK's `semantic-conventions.ts`.
final class SessionSpanProcessor: SpanProcessor {
    let isStartRequired = true
    let isEndRequired = false

    private let store: SessionStore

    init(store: SessionStore = .shared) {
        self.store = store
    }

    func onStart(parentContext: SpanContext?, span: ReadableSpan) {
        // session.id
        if let sessionId = store.currentSessionId {
            span.setAttribute(key: "session.id", value: .string(sessionId))
        }

        // session.previous_id
        if let previousId = store.previousSessionId {
            span.setAttribute(key: "session.previous_id", value: .string(previousId))
        }

        // view.id
        if let viewId = store.currentViewId {
            span.setAttribute(key: "view.id", value: .string(viewId))
        }

        // view.name
        if let viewName = store.currentViewName {
            span.setAttribute(key: "view.name", value: .string(viewName))
        }

        // user.*
        if let user = store.currentUser {
            if let id = user.id {
                span.setAttribute(key: "user.id", value: .string(id))
            }
            if let name = user.name {
                span.setAttribute(key: "user.name", value: .string(name))
            }
            if let fullName = user.fullName {
                span.setAttribute(key: "user.full_name", value: .string(fullName))
            }
            if let email = user.email {
                span.setAttribute(key: "user.email", value: .string(email))
            }
            if !user.extraInfo.isEmpty {
                let reservedKeys: Set<String> = ["id", "name", "full_name", "email"]
                for (key, value) in user.extraInfo where !reservedKeys.contains(key) {
                    span.setAttribute(key: "user.\(key)", value: .string(value))
                }
            }
        }
    }

    func onEnd(span: ReadableSpan) {}

    func shutdown(explicitTimeout: TimeInterval? = nil) {}

    func forceFlush(timeout: TimeInterval? = nil) {}
}
