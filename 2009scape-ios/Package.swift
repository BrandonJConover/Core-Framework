// swift-tools-version: 5.9
import PackageDescription

// Native Swift rev-530 (2009scape) client core.
//
// `Scape530` is pure Swift + Foundation so it builds and tests on Linux
// (CI / cloud containers) as well as macOS and iOS. Platform UI (SwiftUI,
// Metal) lives in the app target and must not leak into this library.
let package = Package(
	name: "Scape530",
	platforms: [
		.iOS(.v16),
		.macOS(.v13),
	],
	products: [
		.library(name: "Scape530", targets: ["Scape530"]),
		.executable(name: "scape530-probe", targets: ["scape530-probe"]),
		.executable(name: "scape530-bench", targets: ["scape530-bench"]),
	],
	targets: [
		// Release builds of the library turn off dynamic exclusivity enforcement: the software rasteriser reads and
		// writes class properties (`Rasteriser3D`, `Scene`, `ScenePicker`) in its innermost loops, and each access
		// otherwise costs a `swift_beginAccess` call (about a quarter of a frame, see PERF.md). The code has no
		// overlapping accesses (the game thread is serial); debug builds and tests keep the checks.
		.target(name: "Scape530", swiftSettings: [.unsafeFlags(["-enforce-exclusivity=unchecked"], .when(configuration: .release))]),
		.executableTarget(name: "scape530-probe", dependencies: ["Scape530"]),
		.executableTarget(name: "scape530-bench", dependencies: ["Scape530"]),
		.testTarget(name: "Scape530Tests", dependencies: ["Scape530"], resources: [.copy("Fixtures")]),
	]
)
