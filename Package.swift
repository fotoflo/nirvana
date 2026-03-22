// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Nirvana",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Nirvana",
            dependencies: [],
            path: "Sources/Nirvana",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SpriteKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "NirvanaTests",
            dependencies: ["Nirvana"],
            path: "Tests/NirvanaTests"
        ),
    ]
)
