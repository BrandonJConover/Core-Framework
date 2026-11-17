import Foundation
import UIKit
import UserNotifications
import Scape530

/// Plugin settings in UserDefaults, one JSON blob per plugin under "plugin.<id>".
final class UserDefaultsPluginSettingsStore: PluginSettingsStore {
	private let defaults: UserDefaults
	init(defaults: UserDefaults = .standard) { self.defaults = defaults }
	func data(forPlugin id: String) -> Data? { defaults.data(forKey: "plugin." + id) }
	func setData(_ data: Data?, forPlugin id: String) {
		if let data { defaults.set(data, forKey: "plugin." + id) } else { defaults.removeObject(forKey: "plugin." + id) }
	}
}

/// Turns plugin notifications into something the player notices: a haptic while the app is on screen, a local
/// notification while it is not.
final class PluginNotifier {
	static let shared = PluginNotifier()
	private let center = UNUserNotificationCenter.current()

	/// Asks for permission (the system shows its prompt once). Call when the player turns on a plugin that notifies.
	func requestAuthorization() {
		center.requestAuthorization(options: [.alert, .sound]) { granted, error in
			if let error { print("[plugins] notification permission: \(error)") }
			print("[plugins] notifications \(granted ? "allowed" : "denied")")
		}
	}

	/// Safe to call from any thread (the client calls it from the game queue).
	func handle(_ n: PluginNotification) {
		DispatchQueue.main.async { [self] in
			if UIApplication.shared.applicationState == .active {
				let gen = UINotificationFeedbackGenerator()
				gen.notificationOccurred(n.kind == .lowHitpoints ? .warning : .success)
				return
			}
			let content = UNMutableNotificationContent()
			content.title = n.title
			content.body = n.body
			content.sound = .default
			// Same identifier per plugin, so a repeat replaces the earlier banner instead of stacking.
			let request = UNNotificationRequest(identifier: "plugin." + n.pluginId + "." + n.kind.rawValue, content: content, trigger: nil)
			center.add(request) { error in
				if let error { print("[plugins] notification failed: \(error)") }
			}
		}
	}
}
