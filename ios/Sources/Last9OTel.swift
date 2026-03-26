import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporterHttp
import URLSessionInstrumentation
import ResourceExtension

/// Last9 OpenTelemetry setup for iOS.
///
/// Uses the client monitoring token flow (same as Browser RUM SDK) with a
/// synthetic origin (`ios://com.your.bundleid`). Auto-instruments URLSession
/// and injects W3C traceparent for backend correlation.
final class Last9OTel {
    static var shared: Last9OTel?

    private let tracerProvider: TracerProviderSdk
    private let urlSessionInstrumentation: URLSessionInstrumentation

    // MARK: - Initialization

    /// Call once in `application(_:didFinishLaunchingWithOptions:)` or SwiftUI `App.init()`.
    ///
    /// ```swift
    /// Last9OTel.initialize(
    ///     endpoint: "<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring",
    ///     clientToken: "<your-client-token>",
    ///     serviceName: "my-ios-app"
    /// )
    /// ```
    @discardableResult
    static func initialize(
        endpoint: String,
        clientToken: String,
        serviceName: String,
        environment: String = "production"
    ) -> Last9OTel {
        let instance = Last9OTel(
            endpoint: endpoint,
            clientToken: clientToken,
            serviceName: serviceName,
            environment: environment
        )
        shared = instance
        return instance
    }

    private init(
        endpoint: String,
        clientToken: String,
        serviceName: String,
        environment: String
    ) {
        // 1. Resource — auto-detected device/OS + custom service attributes
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        var resource = DefaultResources().get()
        resource.merge(other: Resource(attributes: [
            "service.name": .string(serviceName),
            "service.version": .string("\(appVersion)+\(buildNumber)"),
            "deployment.environment": .string(environment),
            "service.namespace": .string("mobile"),
        ]))

        // 2. Synthetic origin — ios://com.your.bundleid
        //    Register this value as the allowed origin when creating the
        //    client monitoring token in the Last9 dashboard.
        let origin = "ios://\(bundleId)"

        // 3. Device ID for client identification (stable per vendor, resets on uninstall)
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

        let traceExporter = OtlpHttpTraceExporter(
            endpoint: URL(string: "\(endpoint)/v1/traces")!,
            config: otlpConfig,
            envVarHeaders: nil
        )

        // 5. Batch span processor (flushes every 5s, max 512 spans per batch)
        let spanProcessor = BatchSpanProcessor(
            spanExporter: traceExporter,
            scheduleDelay: 5,
            maxQueueSize: 2048,
            maxExportBatchSize: 512
        )

        // 6. Register tracer provider globally
        self.tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: spanProcessor)
            .build()
        OpenTelemetry.registerTracerProvider(tracerProvider: self.tracerProvider)

        // 7. URLSession auto-instrumentation
        //    - ALL URLSession calls are traced automatically (method swizzling)
        //    - W3C traceparent header injected into every outgoing request
        //    - Captures: HTTP method, URL, status code, latency
        self.urlSessionInstrumentation = URLSessionInstrumentation(
            configuration: URLSessionInstrumentationConfiguration(
                shouldInstrument: { request in
                    guard let host = request.url?.host else { return true }
                    return !host.contains("last9.io")
                },
                semanticConvention: .stable
            )
        )

        print("[Last9] OTel initialized — \(serviceName) (\(environment)) origin=\(origin)")
    }

    // MARK: - Lifecycle

    /// Flush pending spans. Call in `applicationDidEnterBackground`.
    func flush() {
        tracerProvider.forceFlush()
    }

    /// Shutdown. Call in `applicationWillTerminate`.
    func shutdown() {
        tracerProvider.shutdown()
    }

    // MARK: - Convenience

    /// Get a tracer for custom spans.
    static func tracer(_ name: String = "app") -> Tracer {
        OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: name,
            instrumentationVersion: nil
        )
    }
}
