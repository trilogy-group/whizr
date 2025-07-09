// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Whizr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Whizr",
            targets: ["Whizr"])
    ],
    dependencies: [
        // Add any external dependencies here if needed
        // For now, we're using only native macOS APIs
    ],
    targets: [
        .executableTarget(
            name: "Whizr",
            dependencies: []),
        .testTarget(
            name: "WhizrTests",
            dependencies: ["Whizr"])
    ]
) 