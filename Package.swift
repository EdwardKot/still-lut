// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RawToLogConverter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RawToLogConverter",
            targets: ["RawToLogConverter"]
        )
    ],
    targets: [
        // LibRaw C bridge target (Objective-C++)
        .target(
            name: "LibRawBridge",
            path: "Sources/RawToLogConverter/LibRaw",
            sources: ["LibRawBridge.mm"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../CLibRawHeaders")
            ],
            linkerSettings: [
                .linkedLibrary("raw"),
                .unsafeFlags(["-L/opt/homebrew/lib"], .when(platforms: [.macOS]))
            ]
        ),
        // Main executable target
        .executableTarget(
            name: "RawToLogConverter",
            dependencies: ["LibRawBridge"],
            path: "Sources/RawToLogConverter",
            exclude: ["LibRaw"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
