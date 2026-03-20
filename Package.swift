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
        .library(name: "EMParser", targets: ["EMParser"]),
        .library(name: "EMEditor", targets: ["EMEditor"]),
        .library(name: "EMFile", targets: ["EMFile"]),
        .library(name: "EMSettings", targets: ["EMSettings"]),
        .library(name: "EMApp", targets: ["EMApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .target(name: "EMCore"),
        .target(
            name: "EMParser",
            dependencies: [
                "EMCore",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "EMEditor",
            dependencies: [
                "EMCore",
                "EMParser",
            ]
        ),
        .target(name: "EMFile", dependencies: ["EMCore"]),
        .target(name: "EMSettings", dependencies: ["EMCore"]),
        .target(name: "EMApp", dependencies: ["EMCore", "EMEditor", "EMSettings"]),
        .testTarget(name: "EMCoreTests", dependencies: ["EMCore"]),
        .testTarget(name: "EMParserTests", dependencies: ["EMParser", "EMCore"]),
        .testTarget(name: "EMFileTests", dependencies: ["EMFile", "EMCore"]),
        .testTarget(name: "EMEditorTests", dependencies: ["EMEditor", "EMCore"]),
        .testTarget(name: "EMAppTests", dependencies: ["EMApp"]),
    ]
)
