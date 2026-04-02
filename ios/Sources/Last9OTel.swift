import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporterHttp
import URLSessionInstrumentation
import ResourceExtension

#if canImport(UIKit)
import UIKit
#endif

/// Last9 OpenTelemetry setup for iOS.
///
/// Uses the client monitoring token flow (same as Browser RUM SDK) with a
/// synthetic origin (`ios://com.your.bundleid`). Auto-instruments URLSession
/// and injects W3C traceparent for backend correlation.
///
/// Resource attributes follow OTel semantic conventions:
/// - service.*, device.*, os.*, app.*, telemetry.sdk.*, host.*
///
/// Session, view, and user tracking:
/// - Sessions: auto-managed with 15m inactivity / 4h max duration, persisted to disk
/// - Views: auto-tracked via UIViewController swizzle, or manual `.trackView(name:)` for SwiftUI
/// - Users: `Last9OTel.identify(...)` stamps `user.*` on every span
final class Last9OTel {
    static var shared: Last9OTel?

    private let tracerProvider: TracerProviderSdk
    private let loggerProvider: LoggerProviderSdk?
    private let urlSessionInstrumentation: URLSessionInstrumentation
    private var lifecycleLogger: Logger?
    private let sessionManager: SessionManager
    let viewManager: ViewManager
    private let hangDetector: HangDetector
    let watchdogDetector: WatchdogTerminationDetector
    let appLaunchTracker: AppLaunchTracker
    private let interactionTracker: InteractionTracker
    let networkTimingTracker: NetworkTimingTracker

    // MARK: - Initialization

    /// Call once in `application(_:didFinishLaunchingWithOptions:)` or SwiftUI `App.init()`.
    ///
    /// - Parameters:
    ///   - sessionInactivityTimeout: Session expires after this many seconds of inactivity (default: 15 minutes).
    ///   - enableAutoViewTracking: Swizzle UIViewController to auto-track views (default: true).
    ///   - hangThreshold: Main thread block time to classify as a hang (default: 2 seconds). Set to `0` to disable.
    @discardableResult
    static func initialize(
        endpoint: String,
        clientToken: String,
        serviceName: String,
        environment: String = "production",
        sessionInactivityTimeout: TimeInterval = 15 * 60,
        enableAutoViewTracking: Bool = true,
        hangThreshold: TimeInterval = 2.0
    ) -> Last9OTel {
        // Idempotent — only the first call takes effect
        if let existing = shared { return existing }

        let instance = Last9OTel(
            endpoint: endpoint,
            clientToken: clientToken,
            serviceName: serviceName,
            environment: environment,
            sessionInactivityTimeout: sessionInactivityTimeout,
            enableAutoViewTracking: enableAutoViewTracking,
            hangThreshold: hangThreshold
        )
        shared = instance
        instance.startLifecycleObserver()
        return instance
    }

    private init(
        endpoint: String,
        clientToken: String,
        serviceName: String,
        environment: String,
        sessionInactivityTimeout: TimeInterval,
        enableAutoViewTracking: Bool,
        hangThreshold: TimeInterval
    ) {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        // 1. Resource — OTel semantic conventions for mobile
        let resource = Self.buildResource(serviceName: serviceName, environment: environment)

        // 2. Synthetic origin — ios://com.your.bundleid
        let origin = "ios://\(bundleId)"

        // 3. Device ID for client identification
        let clientId: String
        #if canImport(UIKit)
        clientId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        clientId = UUID().uuidString
        #endif

        // 4. OTLP HTTP exporter → Last9 client monitoring endpoint
        let otlpConfig = OtlpConfiguration(
            timeout: 30,
            compression: .gzip,
            headers: [
                ("X-LAST9-API-TOKEN", "Bearer \(clientToken)"),
                ("X-LAST9-ORIGIN", origin),
                ("Client-ID", clientId),
            ]
        )

        // 5. Trace exporter + processor
        let traceExporter = OtlpHttpTraceExporter(
            endpoint: URL(string: "\(endpoint)/v1/traces")!,
            config: otlpConfig,
            envVarHeaders: nil
        )
        let spanProcessor = BatchSpanProcessor(
            spanExporter: traceExporter,
            scheduleDelay: 5,
            maxQueueSize: 2048,
            maxExportBatchSize: 512
        )

        // 6. Register tracer provider
        //    SessionSpanProcessor is first — it stamps session.id, view.id, user.*
        //    onto every span before BatchSpanProcessor queues it for export.
        let sessionSpanProcessor = SessionSpanProcessor()
        self.tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: sessionSpanProcessor)
            .add(spanProcessor: spanProcessor)
            .build()
        OpenTelemetry.registerTracerProvider(tracerProvider: self.tracerProvider)

        // 7. Log exporter for lifecycle events + crash reporting
        let logExporter = OtlpHttpLogExporter(
            endpoint: URL(string: "\(endpoint)/v1/logs")!,
            config: otlpConfig,
            envVarHeaders: nil
        )
        let logProcessor = BatchLogRecordProcessor(
            logRecordExporter: logExporter,
            scheduleDelay: 5,
            maxQueueSize: 2048,
            maxExportBatchSize: 512
        )
        self.loggerProvider = LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [logProcessor])
            .build()
        OpenTelemetry.registerLoggerProvider(loggerProvider: self.loggerProvider!)
        self.lifecycleLogger = OpenTelemetry.instance.loggerProvider.loggerBuilder(instrumentationScopeName: "device").build()

        // 8. URLSession auto-instrumentation
        self.urlSessionInstrumentation = URLSessionInstrumentation(
            configuration: URLSessionInstrumentationConfiguration(
                shouldInstrument: { request in
                    guard let host = request.url?.host else { return true }
                    return !host.contains("last9.io")
                },
                semanticConvention: .stable
            )
        )

        // 9. Install crash handler
        Self.installCrashHandler()

        // 10. Session + View managers — must be after provider registration
        self.sessionManager = SessionManager(
            tracerProvider: self.tracerProvider,
            inactivityTimeout: sessionInactivityTimeout
        )
        self.viewManager = ViewManager(tracerProvider: self.tracerProvider)
        sessionManager.start()
        viewManager.setup(autoTrackViews: enableAutoViewTracking)

        // 11. Watchdog termination detection — check previous session before starting hang detector
        self.watchdogDetector = WatchdogTerminationDetector()
        watchdogDetector.checkPreviousSession()
        if let sessionId = SessionStore.shared.currentSessionId {
            watchdogDetector.updateSessionId(sessionId)
        }

        // 12. Hang (ANR) detector — background thread monitors main thread responsiveness
        self.hangDetector = HangDetector(hangThreshold: hangThreshold)
        if hangThreshold > 0 {
            hangDetector.start()
        }

        // 13. Signal crash handler (SIGSEGV, SIGABRT, SIGBUS, etc.)
        //     Check for previous signal crash first, then install handlers
        SignalCrashHandler.checkAndReportPreviousCrash()
        SignalCrashHandler.install()

        // 14. App launch time tracking (cold/warm)
        self.appLaunchTracker = AppLaunchTracker(tracerProvider: self.tracerProvider)
        appLaunchTracker.start()

        // 15. User interaction tracking (taps via UIApplication.sendEvent swizzle)
        self.interactionTracker = InteractionTracker(tracerProvider: self.tracerProvider)
        #if canImport(UIKit)
        interactionTracker.install()
        #endif

        // 16. Network timing tracker (DNS/TLS/TTFB from URLSessionTaskMetrics)
        self.networkTimingTracker = NetworkTimingTracker()

        print("[Last9] OTel initialized — \(serviceName) (\(environment)) origin=\(origin)")
    }

    // MARK: - Resource Builder

    /// Builds a Resource with all OTel semantic convention attributes for mobile.
    private static func buildResource(serviceName: String, environment: String) -> Resource {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        // Start with auto-detected attributes (telemetry.sdk.*, os.type, device.model.identifier)
        var resource = DefaultResources().get()

        // service.*
        var attrs: [String: AttributeValue] = [
            "service.name": .string(serviceName),
            "service.version": .string("\(appVersion)+\(buildNumber)"),
            "deployment.environment": .string(environment),
            "service.namespace": .string("mobile"),
        ]

        // device.*
        attrs["device.manufacturer"] = .string("Apple")
        attrs["device.model.identifier"] = .string(Self.machineIdentifier())
        attrs["device.model.name"] = .string(Self.deviceModelName())

        // os.*
        #if canImport(UIKit)
        let device = UIDevice.current
        attrs["os.name"] = .string(device.systemName)
        attrs["os.version"] = .string(device.systemVersion)
        #endif
        attrs["os.type"] = .string("darwin")
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        attrs["os.build_id"] = .string("\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

        // app.*
        attrs["app.build_id"] = .string(buildNumber)
        #if canImport(UIKit)
        attrs["app.installation.id"] = .string(
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
        #endif

        // host.*
        #if arch(arm64)
        attrs["host.arch"] = .string("arm64")
        #elseif arch(x86_64)
        attrs["host.arch"] = .string("x86_64")
        #endif

        resource.merge(other: Resource(attributes: attrs))
        return resource
    }

    // MARK: - Device Model Mapping

    /// Returns the raw machine identifier (e.g. "iPhone15,2").
    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    /// Maps machine identifier to human-readable model name.
    private static func deviceModelName() -> String {
        let id = machineIdentifier()
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        let models: [String: String] = [
            // iPhone 13
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            // iPhone 14
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            // iPhone 15
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            // iPhone 16
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            // iPad
            "iPad13,18": "iPad 10th gen", "iPad13,19": "iPad 10th gen",
            "iPad14,3": "iPad Pro 11-inch 4th gen", "iPad14,4": "iPad Pro 11-inch 4th gen",
            "iPad14,5": "iPad Pro 12.9-inch 6th gen", "iPad14,6": "iPad Pro 12.9-inch 6th gen",
            // Apple TV
            "AppleTV11,1": "Apple TV 4K 2nd gen", "AppleTV14,1": "Apple TV 4K 3rd gen",
        ]
        return models[id] ?? id
        #endif
    }

    // MARK: - App Lifecycle Events (OTel semantic convention: device.app.lifecycle)

    private func startLifecycleObserver() {
        #if canImport(UIKit)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
        #endif
    }

    #if canImport(UIKit)
    @objc private func appDidBecomeActive() {
        emitLifecycleEvent(state: "active")
        watchdogDetector.updateAppState("foreground")
    }
    @objc private func appWillResignActive() { emitLifecycleEvent(state: "inactive") }
    @objc private func appDidEnterBackground() {
        emitLifecycleEvent(state: "background")
        watchdogDetector.updateAppState("background")
        flush()
    }
    @objc private func appWillEnterForeground() { emitLifecycleEvent(state: "foreground") }
    @objc private func appWillTerminate() {
        emitLifecycleEvent(state: "terminate")
        shutdown()
    }
    #endif

    /// Emits a `device.app.lifecycle` log event per OTel semantic conventions.
    private func emitLifecycleEvent(state: String) {
        lifecycleLogger?.logRecordBuilder()
            .setBody(.string("device.app.lifecycle"))
            .setSeverity(.info)
            .setAttributes([
                "event.name": .string("device.app.lifecycle"),
                "ios.app.state": .string(state),
            ])
            .emit()
    }

    // MARK: - Crash Handler (exception events with FATAL severity)

    private static func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            // Mark crash so watchdog detector doesn't double-report on next launch
            Last9OTel.shared?.watchdogDetector.markCrashHandlerFired()

            let logger = OpenTelemetry.instance.loggerProvider
                .loggerBuilder(instrumentationScopeName: "crash")
                .build()

            logger.logRecordBuilder()
                .setBody(.string("exception"))
                .setSeverity(.fatal)
                .setAttributes([
                    "event.name": .string("exception"),
                    "exception.type": .string(exception.name.rawValue),
                    "exception.message": .string(exception.reason ?? ""),
                    "exception.stacktrace": .string(exception.callStackSymbols.joined(separator: "\n")),
                ])
                .emit()

            // Force flush before crash terminates the process
            Last9OTel.shared?.tracerProvider.forceFlush()
            Last9OTel.shared?.loggerProvider?.forceFlush()
            // Give the exporter time to send
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: - Lifecycle

    /// Flush pending spans and logs. Call in `applicationDidEnterBackground`.
    func flush() {
        tracerProvider.forceFlush()
        loggerProvider?.forceFlush()
    }

    /// Shutdown all providers. Call in `applicationWillTerminate`.
    func shutdown() {
        hangDetector.stop()
        appLaunchTracker.shutdown()
        watchdogDetector.markCleanShutdown()
        viewManager.shutdown()
        sessionManager.shutdown()
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        #endif
        tracerProvider.shutdown()
        loggerProvider?.shutdown()
    }

    // MARK: - Convenience

    /// Get a tracer for custom spans.
    static func tracer(_ name: String = "app") -> Tracer {
        OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: name,
            instrumentationVersion: nil
        )
    }

    // MARK: - User Identification

    /// Set the current user. Attributes are injected into every subsequent span.
    ///
    ///     Last9OTel.identify(id: "u_123", name: "Alice", email: "alice@example.com")
    static func identify(
        id: String? = nil,
        name: String? = nil,
        fullName: String? = nil,
        email: String? = nil,
        extraInfo: [String: String] = [:]
    ) {
        let user = UserInfo(id: id, name: name, fullName: fullName, email: email, extraInfo: extraInfo)
        SessionStore.shared.setUser(user)
    }

    /// Clear the current user identity.
    static func clearUser() {
        SessionStore.shared.setUser(nil)
    }

    // MARK: - Manual View Tracking

    /// Manually start a new view (for SwiftUI or custom navigation).
    /// Ends any currently active view first.
    ///
    ///     Last9OTel.startView(name: "Checkout")
    static func startView(name: String) {
        shared?.viewManager.startView(name: name)
    }

    /// End the current view manually.
    static func endView() {
        shared?.viewManager.endCurrentView()
    }
}
