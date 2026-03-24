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
        .library(name: "EMFormatter", targets: ["EMFormatter"]),
        .library(name: "EMDoctor", targets: ["EMDoctor"]),
        .library(name: "EMEditor", targets: ["EMEditor"]),
        .library(name: "EMFile", targets: ["EMFile"]),
        .library(name: "EMAI", targets: ["EMAI"]),
        .library(name: "EMCloud", targets: ["EMCloud"]),
        .library(name: "EMGit", targets: ["EMGit"]),
        .library(name: "EMSettings", targets: ["EMSettings"]),
        .library(name: "EMApp", targets: ["EMApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        // SPIKE-007: tree-sitter evaluation for syntax highlighting
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", from: "0.7.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", from: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", from: "0.25.0"),
    ],
    targets: [
        .target(
            name: "EMCore",
            resources: [
                .copy("Resources/Fonts"),
            ]
        ),
        .target(
            name: "EMParser",
            dependencies: [
                "EMCore",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "EMFormatter",
            dependencies: [
                "EMCore",
                "EMParser",
            ]
        ),
        .target(
            name: "EMDoctor",
            dependencies: [
                "EMCore",
                "EMParser",
            ]
        ),
        .target(
            name: "EMEditor",
            dependencies: [
                "EMCore",
                "EMParser",
                "EMFormatter",
                "EMDoctor",
                // SPIKE-007: tree-sitter for syntax highlighting evaluation
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(name: "EMFile", dependencies: ["EMCore"]),
        .target(name: "EMAI", dependencies: ["EMCore"]),
        .target(name: "EMCloud", dependencies: ["EMCore"]),
        .target(name: "EMGit", dependencies: ["EMCore"]),
        .target(name: "EMSettings", dependencies: ["EMCore"]),
        .target(name: "EMApp", dependencies: ["EMCore", "EMEditor", "EMFile", "EMFormatter", "EMAI", "EMCloud", "EMGit", "EMSettings"]),
        .testTarget(name: "EMCoreTests", dependencies: ["EMCore"]),
        .testTarget(name: "EMParserTests", dependencies: ["EMParser", "EMCore"]),
        .testTarget(name: "EMFileTests", dependencies: ["EMFile", "EMCore"]),
        .testTarget(name: "EMFormatterTests", dependencies: ["EMFormatter", "EMParser", "EMCore"]),
        .testTarget(name: "EMDoctorTests", dependencies: ["EMDoctor", "EMParser", "EMCore"]),
        .testTarget(name: "EMEditorTests", dependencies: [
            "EMEditor", "EMParser", "EMCore",
            .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
        ]),
        .testTarget(name: "EMAITests", dependencies: ["EMAI", "EMCore"]),
        .testTarget(name: "EMCloudTests", dependencies: ["EMCloud", "EMCore"]),
        .testTarget(name: "EMSettingsTests", dependencies: ["EMSettings", "EMCore"]),
        .testTarget(name: "EMGitTests", dependencies: ["EMGit", "EMCore"]),
        .testTarget(name: "EMAppTests", dependencies: ["EMApp", "EMSettings", "EMAI", "EMCore"]),
        .testTarget(name: "PerformanceRegressionTests", dependencies: [
            "EMCore", "EMParser", "EMFormatter", "EMEditor", "EMAI", "EMFile",
        ]),
    ]
)
