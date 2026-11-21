// swift-tools-version:5.9
// Pure-Swift port of the rsc-c Classic client (2003scape/rsc-c, AGPL-3.0).
// No UIKit here: the core builds and tests on Linux, and the iOS app wraps it.
import PackageDescription

let package = Package(
    name: "RSCClassic",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "RSCClassic", targets: ["RSCClassic"]),
    ],
    targets: [
        .target(name: "RSCClassic", path: "Sources/RSCClassic"),
        .testTarget(name: "RSCClassicTests", dependencies: ["RSCClassic"],
                    path: "Tests/RSCClassicTests"),
    ]
)
