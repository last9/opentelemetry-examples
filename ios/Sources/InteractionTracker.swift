import Foundation
import ObjectiveC
import OpenTelemetryApi

#if canImport(UIKit)
import UIKit
#endif

/// Tracks user interactions (taps, scrolls, swipes) by swizzling `UIApplication.sendEvent(_:)`.
///
/// Each interaction is emitted as a span with:
/// - `interaction.type`: tap, scroll, swipe
/// - `interaction.target.class`: the responder class name
/// - `interaction.target.accessibility_label`: if set
/// - `interaction.target.accessibility_identifier`: if set
///
/// Follows Sentry's approach of swizzling `sendEvent` rather than Datadog's gesture recognizer approach.
final class InteractionTracker {
    private let tracer: Tracer
    private var isInstalled = false

    init(tracerProvider: TracerProvider) {
        self.tracer = tracerProvider.get(
            instrumentationName: "interaction",
            instrumentationVersion: nil
        )
    }

    #if canImport(UIKit)

    func install() {
        guard !isInstalled else { return }

        // Store reference so swizzled method can access it
        InteractionTracker.shared = self

        let appClass: AnyClass = UIApplication.self
        if let original = class_getInstanceMethod(appClass, #selector(UIApplication.sendEvent(_:))),
           let swizzled = class_getInstanceMethod(appClass, #selector(UIApplication.last9_sendEvent(_:))) {
            method_exchangeImplementations(original, swizzled)
        }

        isInstalled = true
    }

    static weak var shared: InteractionTracker?

    func handleEvent(_ event: UIEvent) {
        guard event.type == .touches else { return }
        guard let touches = event.allTouches else { return }

        for touch in touches {
            switch touch.phase {
            case .ended:
                handleTap(touch)
            default:
                break
            }
        }
    }

    private func handleTap(_ touch: UITouch) {
        guard let view = touch.view else { return }

        let targetClass = String(describing: type(of: view))

        // Skip system keyboard and internal views
        if targetClass.hasPrefix("_UI") || targetClass.hasPrefix("UIRemote") { return }

        var attrs: [(String, String)] = [
            ("interaction.type", "tap"),
            ("interaction.target.class", targetClass),
        ]

        if let label = view.accessibilityLabel, !label.isEmpty {
            attrs.append(("interaction.target.accessibility_label", label))
        }

        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
            attrs.append(("interaction.target.accessibility_identifier", identifier))
        }

        // For UIControl subclasses, include the control type
        if let control = view as? UIControl {
            attrs.append(("interaction.target.control_type", describeControlType(control)))
        }

        let span = tracer.spanBuilder(spanName: "interaction.tap")
            .startSpan()
        for (key, value) in attrs {
            span.setAttribute(key: key, value: value)
        }
        span.end()
    }

    private func describeControlType(_ control: UIControl) -> String {
        switch control {
        case is UIButton: return "button"
        case is UISwitch: return "switch"
        case is UISlider: return "slider"
        case is UITextField: return "text_field"
        case is UISegmentedControl: return "segmented_control"
        case is UIStepper: return "stepper"
        default: return "control"
        }
    }

    #endif
}

// MARK: - UIApplication Swizzle Extension

#if canImport(UIKit)

extension UIApplication {
    @objc func last9_sendEvent(_ event: UIEvent) {
        // Call original (swapped via method_exchangeImplementations)
        self.last9_sendEvent(event)

        // Track the interaction
        InteractionTracker.shared?.handleEvent(event)
    }
}

#endif
