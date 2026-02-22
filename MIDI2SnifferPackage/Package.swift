// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MIDI2SnifferPackage",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MIDI2SnifferKit",
            targets: ["MIDI2SnifferKit"]
        ),
    ],
    dependencies: [
        .package(path: "../../MIDI2Kit"),
    ],
    targets: [
        .target(
            name: "MIDI2SnifferKit",
            dependencies: [
                .product(name: "MIDI2Kit", package: "MIDI2Kit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
