// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Last9OTelExample",
    platforms: [.iOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Last9OTelExample",
            dependencies: [
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
                .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
                .product(name: "ResourceExtension", package: "opentelemetry-swift"),
                .product(name: "NetworkStatus", package: "opentelemetry-swift"),
            ],
            path: "Sources"
        )
    ]
)
