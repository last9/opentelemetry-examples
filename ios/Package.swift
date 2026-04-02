// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Last9OTelExample",
    platforms: [.iOS(.v13), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/last9/last9-ios-swift-sdk", from: "0.1.2"),
        // OpenTelemetryApi is needed directly for custom span creation in examples
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Last9OTelExample",
            dependencies: [
                .product(name: "Last9RUM", package: "last9-ios-swift-sdk"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
            ],
            path: "Sources"
        )
    ]
)
