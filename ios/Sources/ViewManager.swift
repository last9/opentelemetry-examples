import Foundation
import ObjectiveC
import OpenTelemetryApi
import OpenTelemetrySdk

#if canImport(UIKit)
import UIKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - ViewManager

/// Tracks screen views automatically (UIKit swizzle) and manually (API + SwiftUI modifier).
///
/// Each view gets a unique `view.id` (UUID) and a `view.name` derived from the
/// UIViewController class name (e.g., `"HomeViewController"`). On view end, `view.time_spent`
/// is recorded in milliseconds.
///
/// Listens to `.last9SessionDidRollover` to rotate the view span when the session changes.
final class ViewManager {
    private let store: SessionStore
    private let tracer: Tracer
    private var activeSpan: Span?
    private var sessionRolloverObserver: NSObjectProtocol?

    init(tracerProvider: TracerProvider, store: SessionStore = .shared) {
        self.store = store
        self.tracer = tracerProvider.get(
            instrumentationName: "navigation",
            instrumentationVersion: nil
        )
    }

    // MARK: - Setup

    func setup(autoTrackViews: Bool = true) {
        #if canImport(UIKit)
        if autoTrackViews {
            ViewSwizzler.install(viewManager: self)
        }
        #endif

        sessionRolloverObserver = NotificationCenter.default.addObserver(
            forName: .last9SessionDidRollover,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSessionRollover()
        }
    }

    // MARK: - Public API

    func startView(name: String) {
        // End existing view if any
        endCurrentView()

        let viewId = UUID().uuidString
        store.beginView(id: viewId, name: name)

        let span = tracer.spanBuilder(spanName: "View")
            .setAttribute(key: "view.id", value: viewId)
            .setAttribute(key: "view.name", value: name)
            .startSpan()
        activeSpan = span
    }

    func endCurrentView() {
        guard let span = activeSpan else { return }

        if let timeSpent = store.endView() {
            span.setAttribute(key: "view.time_spent", value: timeSpent)
        }
        span.end()
        activeSpan = nil
    }

    func shutdown() {
        endCurrentView()
        if let obs = sessionRolloverObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Session Rollover

    private func handleSessionRollover() {
        let currentName = store.currentViewName ?? "Unknown"
        endCurrentView()
        startView(name: currentName)
    }
}

// MARK: - UIViewController Swizzling

#if canImport(UIKit)

/// System VC classes to skip during auto-tracking.
private let skippedClassNames: Set<String> = [
    "UINavigationController",
    "UITabBarController",
    "UIPageViewController",
    "UISplitViewController",
    "UIAlertController",
    "UIInputWindowController",
    "UIEditingOverlayViewController",
    "UICompatibilityInputViewController",
    "UISystemInputAssistantViewController",
]

/// Class name prefixes for Apple-internal VCs to skip.
private let skippedPrefixes = ["_UI", "_AV", "_MK", "_CN"]

enum ViewSwizzler {
    static var isInstalled = false
    static weak var viewManager: ViewManager?

    static func install(viewManager: ViewManager) {
        guard !isInstalled else { return }
        self.viewManager = viewManager

        let vcClass: AnyClass = UIViewController.self

        // Swizzle viewDidAppear — methods defined in UIViewController extension below
        if let original = class_getInstanceMethod(vcClass, #selector(UIViewController.viewDidAppear(_:))),
           let swizzled = class_getInstanceMethod(vcClass, #selector(UIViewController.last9_viewDidAppear(_:))) {
            method_exchangeImplementations(original, swizzled)
        }

        // Swizzle viewDidDisappear
        if let original = class_getInstanceMethod(vcClass, #selector(UIViewController.viewDidDisappear(_:))),
           let swizzled = class_getInstanceMethod(vcClass, #selector(UIViewController.last9_viewDidDisappear(_:))) {
            method_exchangeImplementations(original, swizzled)
        }

        isInstalled = true
    }

    static func shouldTrack(className: String) -> Bool {
        if skippedClassNames.contains(className) { return false }
        for prefix in skippedPrefixes {
            if className.hasPrefix(prefix) { return false }
        }
        if className.contains("HostingController") { return false }
        return true
    }
}

// MARK: - UIViewController Extensions

private var last9ViewNameKey: UInt8 = 0

extension UIViewController {
    /// Override the auto-generated view name for this controller.
    /// Set in `viewDidLoad()` to customize the name that appears in Last9 RUM.
    var last9ViewName: String? {
        get { objc_getAssociatedObject(self, &last9ViewNameKey) as? String }
        set { objc_setAssociatedObject(self, &last9ViewNameKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Swizzled `viewDidAppear`. After `method_exchangeImplementations`,
    /// calling `last9_viewDidAppear` actually invokes the **original** `viewDidAppear`
    /// (because the IMPs are swapped). This is the standard ObjC swizzle pattern.
    @objc func last9_viewDidAppear(_ animated: Bool) {
        // Calls original viewDidAppear (via swapped IMP)
        self.last9_viewDidAppear(animated)

        let className = String(describing: type(of: self))
        guard ViewSwizzler.shouldTrack(className: className) else { return }

        let viewName = self.last9ViewName ?? className
        ViewSwizzler.viewManager?.startView(name: viewName)
    }

    @objc func last9_viewDidDisappear(_ animated: Bool) {
        self.last9_viewDidDisappear(animated)

        let className = String(describing: type(of: self))
        guard ViewSwizzler.shouldTrack(className: className) else { return }

        ViewSwizzler.viewManager?.endCurrentView()
    }
}

#endif

// MARK: - SwiftUI View Modifier

#if canImport(SwiftUI)

/// Tracks a SwiftUI view as a RUM view with the given name.
///
/// Usage:
/// ```swift
/// ContentView()
///     .trackView(name: "Home")
/// ```
@available(iOS 13.0, *)
struct TrackViewModifier: SwiftUI.ViewModifier {
    let name: String

    func body(content: Content) -> some SwiftUI.View {
        content
            .onAppear {
                Last9OTel.startView(name: name)
            }
            .onDisappear {
                Last9OTel.endView()
            }
    }
}

@available(iOS 13.0, *)
public extension SwiftUI.View {
    /// Track this SwiftUI view as a RUM screen view.
    ///
    /// ```swift
    /// NavigationView {
    ///     HomeView()
    ///         .trackView(name: "Home")
    /// }
    /// ```
    func trackView(name: String) -> some SwiftUI.View {
        modifier(TrackViewModifier(name: name))
    }
}

#endif
