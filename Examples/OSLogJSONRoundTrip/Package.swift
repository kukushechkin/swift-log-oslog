// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "OSLogJSONRoundTrip",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
    ],
    targets: [
        .executableTarget(
            name: "OSLogJSONRoundTrip",
            dependencies: [
                .product(name: "OSLogHandler", package: "swift-log-oslog"),
                .product(name: "SensitivityAttribute", package: "swift-log-oslog"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources"
        )
    ]
)
