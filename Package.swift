// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TransferKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TransferKit", targets: ["TransferKit"])
    ],
    targets: [
        .target(name: "TransferKit"),
        .testTarget(
            name: "TransferKitTests",
            dependencies: ["TransferKit"]
        ),
    ],
    // Swift 6 language mode: strict concurrency checking on from day one.
    swiftLanguageModes: [.v6]
)
