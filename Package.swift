// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EasyMarkdown",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "EMCore", targets: ["EMCore"]),
        .library(name: "EMFile", targets: ["EMFile"]),
        .library(name: "EMSettings", targets: ["EMSettings"]),
        .library(name: "EMApp", targets: ["EMApp"]),
    ],
    targets: [
        .target(name: "EMCore"),
        .target(name: "EMFile", dependencies: ["EMCore"]),
        .target(name: "EMSettings", dependencies: ["EMCore"]),
        .target(name: "EMApp", dependencies: ["EMCore", "EMSettings"]),
        .testTarget(name: "EMCoreTests", dependencies: ["EMCore"]),
        .testTarget(name: "EMFileTests", dependencies: ["EMFile", "EMCore"]),
        .testTarget(name: "EMAppTests", dependencies: ["EMApp"]),
    ]
)
