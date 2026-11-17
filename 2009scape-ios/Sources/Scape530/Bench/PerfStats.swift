import Foundation

/// Cheap section timers for the benchmark (`scape530-bench`). Off by default: every probe is a single
/// branch on `PerfStats.enabled`, so shipping builds pay nothing measurable.
public enum PerfStats {
	public enum Section: Int, CaseIterable {
		case frame, scene, place, sceneDraw, ground, models, copy3D, overlays, ui, minimap, cycle
		public var label: String {
			switch self {
			case .frame: return "frame total"
			case .scene: return "scene (renderScene)"
			case .place: return "  actors + effects placement"
			case .sceneDraw: return "  scene.draw (ground+models)"
			case .ground: return "    ground tiles"
			case .models: return "    models (locs, actors, items)"
			case .copy3D: return "  3D buffer -> frame"
			case .overlays: return "  overlays (names, hits)"
			case .ui: return "interfaces"
			case .minimap: return "minimap"
			case .cycle: return "client cycle (world.cycle)"
			}
		}
	}

	nonisolated(unsafe) public static var enabled = false
	nonisolated(unsafe) static var nanos = [UInt64](repeating: 0, count: Section.allCases.count)

	@inline(__always) public static func now() -> UInt64 { enabled ? DispatchTime.now().uptimeNanoseconds : 0 }

	@inline(__always) static func add(_ s: Section, since t0: UInt64) {
		if enabled { nanos[s.rawValue] &+= DispatchTime.now().uptimeNanoseconds &- t0 }
	}

	public static func reset() { for i in 0..<nanos.count { nanos[i] = 0 } }
	public static func seconds(_ s: Section) -> Double { Double(nanos[s.rawValue]) / 1e9 }
}
