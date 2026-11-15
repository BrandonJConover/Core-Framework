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
	],
	targets: [
		.target(name: "Scape530"),
		.executableTarget(name: "scape530-probe", dependencies: ["Scape530"]),
		.testTarget(name: "Scape530Tests", dependencies: ["Scape530"], resources: [.copy("Fixtures")]),
	]
)
