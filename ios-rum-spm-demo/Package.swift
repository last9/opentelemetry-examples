// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Last9RUMSPMDemo",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        .library(name: "RUMSPMDemoApp", targets: ["RUMSPMDemoApp"]),
    ],
    targets: [
        .binaryTarget(
            name: "Last9RUM",
            url: "https://cdn.last9.io/rum-sdk/ios/builds/0.9.0/Last9RUM.xcframework.zip",
            checksum: "a340f15d22d1d594731c3eff17bbc806f1c732962aa39daab072451ecde23ebf"
        ),
        .target(
            name: "RUMSPMDemoApp",
            dependencies: ["Last9RUM"],
            path: "Sources/RUMSPMDemoApp"
        ),
    ]
)
