// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ModuleSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "ModuleSDK",targets: ["ModuleSDK"])
    ],
    dependencies: [
        // Note: this needs to be synced with project.yml value somehow.
        .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "1.1.20"),
    ],
    targets: [
        .target(
            name: "ModuleSDK",
            dependencies: [.product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")],
            path: "Sources"
        ),
        .testTarget(
            name: "ModuleSDKTests",
            dependencies: ["ModuleSDK"],
            path: "Tests"
        ),
    ]
)
