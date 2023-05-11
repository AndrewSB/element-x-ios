// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ModuleSDKConfig",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ModuleSDKConfig",
            targets: ["ModuleSDKConfig"]),
    ],
    dependencies: [
        .package(path: "../ModuleSDK"),
    ],
    targets: [
        .target(
            name: "ModuleSDKConfig",
            dependencies: [
                "ModuleSDK",
            ]),
        .testTarget(
            name: "ModuleSDKConfigTests",
            dependencies: ["ModuleSDKConfig"]),
    ]
)
