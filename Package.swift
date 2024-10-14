// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Ambience",
    platforms: [
        .iOS(.v16),
        .visionOS(.v1),
        .tvOS(.v16),
        .watchOS(.v9),
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Ambience",
            targets: ["Ambience"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tid-kijyun/Kanna.git", from: "5.3.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Ambience",
            dependencies: ["Kanna"]
        ),
        .testTarget(
            name: "AmbienceTests",
            dependencies: ["Ambience"]
        ),
    ]
)
