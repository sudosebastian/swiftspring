// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftspringKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SwiftspringKit", targets: ["SwiftspringKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftspringKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/SwiftspringKit"
        ),
        .testTarget(
            name: "SwiftspringKitTests",
            dependencies: ["SwiftspringKit"],
            path: "Tests/SwiftspringKitTests"
        ),
    ]
)
