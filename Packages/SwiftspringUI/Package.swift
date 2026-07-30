// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftspringUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SwiftspringUI", targets: ["SwiftspringUI"]),
    ],
    dependencies: [
        .package(path: "../SwiftspringKit"),
    ],
    targets: [
        .target(
            name: "SwiftspringUI",
            dependencies: ["SwiftspringKit"],
            path: "Sources/SwiftspringUI"
        ),
    ]
)
