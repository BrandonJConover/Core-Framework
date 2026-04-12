// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenRSC",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "OpenRSC",
            path: "OpenRSC/Sources",
            resources: [
                .process("Rendering/Shaders.metal")
            ]
        )
    ]
)
