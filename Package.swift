// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TransferKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TransferKit", targets: ["TransferKit"]),
        .library(name: "TransferKitAWS", targets: ["TransferKitAWS"]),
        .executable(name: "lvs3", targets: ["lvs3"]),
        .executable(name: "LargeVideoToS3App", targets: ["LargeVideoToS3App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0")
    ],
    targets: [
        // Core engine — no AWS dependency, fully testable.
        .target(name: "TransferKit"),

        // AWS-backed S3 client, isolated so the core stays SDK-free.
        .target(
            name: "TransferKitAWS",
            dependencies: [
                "TransferKit",
                .product(name: "AWSS3", package: "aws-sdk-swift"),
            ]
        ),

        // Command-line driver for real uploads against a test bucket.
        .executableTarget(
            name: "lvs3",
            dependencies: ["TransferKit", "TransferKitAWS"]
        ),

        // SwiftUI macOS app (run with `swift run LargeVideoToS3App`).
        .executableTarget(
            name: "LargeVideoToS3App",
            dependencies: ["TransferKit", "TransferKitAWS"]
        ),

        .testTarget(name: "TransferKitTests", dependencies: ["TransferKit"]),
    ],
    swiftLanguageModes: [.v6]
)
