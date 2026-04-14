// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenRSC",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "OpenRSC",
            targets: ["OpenRSC"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenRSC",
            dependencies: [],
            path: "OpenRSC/Sources",
            resources: [
                .process("Rendering/Shaders.metal"),
                .copy("WebClient")
            ]
        ),
    ]
)
