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
        // rsc-c (the same C engine as the WebAssembly browser client) compiled
        // natively, with an SDL2-subset shim. See RSCEngine/README.md.
        .target(
            name: "RSCEngine",
            path: "RSCEngine",
            exclude: ["tools", "rsc-cache", "README.md", "rsc-c-src/COPYING"],
            sources: ["rsc-c-src", "shim"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("shim"),
                .define("SDL2"),
                .define("RENDER_SW"),
                // rsc-c's "ANDROID" path is its mobile SDL2 target: touch
                // input, 360px-tall scaled UI, SDL_GetPrefPath config.
                .define("ANDROID"),
                // rsc-c's main() runs on the engine thread as rsc_c_main().
                .define("main", to: "rsc_c_main"),
                .unsafeFlags(["-std=gnu99", "-fwrapv", "-w"])
            ]
        ),
        .target(
            name: "OpenRSC",
            dependencies: ["RSCEngine"],
            path: "OpenRSC/Sources",
            resources: [
                .process("Rendering/Shaders.metal"),
                .copy("WebClient"),
                .copy("../GameObjectDef.xml"),
                .copy("../DoorDef.xml"),
                .copy("../TileDef.xml"),
                .copy("../NpcDefs.json"),
                .copy("../ItemDefs.json"),
                .copy("../Resources")
            ]
        ),
        .testTarget(
            name: "OpenRSCTests",
            dependencies: ["OpenRSC"],
            path: "Tests/RenderTest",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
