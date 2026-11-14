// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlikConnector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FlikConnector", targets: ["FlikConnector"])
    ],
    targets: [
        .executableTarget(
            name: "FlikConnector",
            path: "Sources/FlikConnector",
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"])
            ]
        )
    ]
)
