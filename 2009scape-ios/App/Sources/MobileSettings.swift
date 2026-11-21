import Foundation
import Scape530

/// User-facing options for the touch layer, stored in UserDefaults (the Settings sheet binds the same keys with @AppStorage).
enum MobileSettings {
	static let mobileMenuKey = "ui.mobileMenu"
	static let tapToDropKey = "ui.tapToDrop"
	static let smoothScalingKey = "ui.smoothScaling"
	static let hapticsKey = "ui.haptics"
	static let smoothMotionKey = "ui.smoothMotion"
	static let opaqueSidePanelKey = "ui.opaqueSidePanel"
	static let frameStatsKey = "ui.frameStats"
	static let interfaceSizeKey = "ui.interfaceSize"
	static let gpuRendererKey = "gfx.gpuRenderer"
	static let gpuDrawDistanceKey = "gfx.drawDistance"
	static let gpuFogKey = "gfx.fog"
	static let gpuAntialiasKey = "gfx.msaa"

	private static func bool(_ key: String, _ fallback: Bool) -> Bool {
		UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
	}

	/// Big touch-friendly option list instead of rt4's tiny popup.
	static var mobileMenu: Bool { bool(mobileMenuKey, true) }
	/// Tapping an inventory item drops it.
	static var tapToDrop: Bool { bool(tapToDropKey, false) }
	/// Bilinear (true) or nearest (false) when the game is scaled to the screen.
	static var smoothScaling: Bool { bool(smoothScalingKey, true) }
	static var haptics: Bool { bool(hapticsKey, true) }
	/// Draw actors and the camera between rt4's 50 Hz client cycles (smooth at 60/120 Hz) instead of stepping at 50 Hz.
	static var smoothMotion: Bool { bool(smoothMotionKey, true) }
	/// Draw the resizable side panel background opaque (rt4 draws it 60% opaque, so the world shows through).
	static var opaqueSidePanel: Bool { bool(opaqueSidePanelKey, true) }
	/// Small fps / ms-per-frame / cycles-per-second readout in the corner.
	static var frameStats: Bool { bool(frameStatsKey, false) }
	/// 0 normal (rt4 765x503 minimum canvas), 1 large, 2 larger.
	static var interfaceSize: Int { UserDefaults.standard.object(forKey: interfaceSizeKey) as? Int ?? 0 }

	/// Draw the 3D scene on the GPU (Metal) instead of with the faithful software rasteriser.
	static var gpuRenderer: Bool { bool(gpuRendererKey, false) }

	/// Settings for the GPU renderer: draw distance in tiles (the software renderer's is 25), fog, 4x MSAA.
	static var gpuSettings: GPURenderSettings {
		var s = GPURenderSettings()
		let d = UserDefaults.standard.object(forKey: gpuDrawDistanceKey) as? Double ?? Double(s.drawDistanceTiles)
		s.drawDistanceTiles = Int(d.rounded())
		s.fogEnabled = bool(gpuFogKey, true)
		s.msaaSamples = bool(gpuAntialiasKey, true) ? 4 : 1
		return s
	}
}
