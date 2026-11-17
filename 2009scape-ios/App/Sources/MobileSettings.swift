import Foundation

/// User-facing options for the touch layer, stored in UserDefaults (the Settings sheet binds the same keys with @AppStorage).
enum MobileSettings {
	static let mobileMenuKey = "ui.mobileMenu"
	static let tapToDropKey = "ui.tapToDrop"
	static let smoothScalingKey = "ui.smoothScaling"
	static let hapticsKey = "ui.haptics"
	static let smoothMotionKey = "ui.smoothMotion"

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
}
