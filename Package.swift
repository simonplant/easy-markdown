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
        .library(name: "EMSettings", targets: ["EMSettings"]),
        .library(name: "EMApp", targets: ["EMApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
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
            ]
        ),
        .target(name: "EMFile", dependencies: ["EMCore"]),
        .target(name: "EMAI", dependencies: ["EMCore"]),
        .target(name: "EMCloud", dependencies: ["EMCore"]),
        .target(name: "EMSettings", dependencies: ["EMCore"]),
        .target(name: "EMApp", dependencies: ["EMCore", "EMEditor", "EMFile", "EMFormatter", "EMAI", "EMCloud", "EMSettings"]),
        .testTarget(name: "EMCoreTests", dependencies: ["EMCore"]),
        .testTarget(name: "EMParserTests", dependencies: ["EMParser", "EMCore"]),
        .testTarget(name: "EMFileTests", dependencies: ["EMFile", "EMCore"]),
        .testTarget(name: "EMFormatterTests", dependencies: ["EMFormatter", "EMParser", "EMCore"]),
        .testTarget(name: "EMDoctorTests", dependencies: ["EMDoctor", "EMParser", "EMCore"]),
        .testTarget(name: "EMEditorTests", dependencies: ["EMEditor", "EMParser", "EMCore"]),
        .testTarget(name: "EMAITests", dependencies: ["EMAI", "EMCore"]),
        .testTarget(name: "EMCloudTests", dependencies: ["EMCloud", "EMCore"]),
        .testTarget(name: "EMSettingsTests", dependencies: ["EMSettings", "EMCore"]),
        .testTarget(name: "EMAppTests", dependencies: ["EMApp", "EMSettings", "EMAI", "EMCore"]),
    ]
)
